
# -----------------------------------------------------------------------------
# Route 53 Hosted Zone for lab.example.com
# This creates the zone — you then point Cloudflare NS records here
# -----------------------------------------------------------------------------
resource "aws_route53_zone" "lab" {
  name = local.fqdn

  tags = {
    Name    = "${var.project_name}-zone"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# ACM Certificate — must be in us-east-1 for CloudFront
# Uses DNS validation — Terraform creates the validation CNAME in Route 53
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "lab" {
  provider          = aws.us_east_1
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    # Create new cert before destroying old one
    # Prevents downtime during cert rotation
    create_before_destroy = true
  }

  tags = {
    Name    = "${var.project_name}-cert"
    Project = var.project_name
  }
}

# Create the DNS validation record in Route 53
# ACM tells us what CNAME to create — we create it here
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.lab.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.lab.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# Wait for ACM to validate the certificate
# This block waits until ACM confirms the CNAME was seen
# Will timeout if NS delegation isn't done in Cloudflare first
resource "aws_acm_certificate_validation" "lab" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.lab.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# -----------------------------------------------------------------------------
# WAF Web ACL — attached to CloudFront distribution
# WAF rules run at the edge before requests reach your origin
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "main" {
  provider    = aws.us_east_1
  name        = "${var.project_name}-waf"
  description = "WAF rules for arch-lab CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 1: Rate limiting — max 1000 requests per 5 minutes per IP
  # Protects against brute force and basic DDoS
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules — Common Rule Set
  # Covers OWASP Top 10: SQL injection, XSS, path traversal, etc.
  # AWS maintains and updates these rules — you don't manage them
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Known Bad Inputs — blocks requests with known malicious patterns
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name    = "${var.project_name}-waf"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# CloudFront Distribution
# Origin = your ALB from Lab 1
# Viewers connect via HTTPS to lab.example.com
# CloudFront connects to ALB via HTTP (internal AWS network)
# -----------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} distribution"
  default_root_object = "index.html"
  aliases             = [local.fqdn]
  web_acl_id          = aws_wafv2_web_acl.main.arn
  price_class         = "PriceClass_100" # US, Canada, Europe only — cheapest

  # Origin — your ALB
  origin {
    domain_name = local.alb_dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # ALB serves HTTP, CloudFront adds HTTPS
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default cache behavior — applies to all paths
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https" # HTTP → HTTPS redirect

    # Minimal caching for dynamic content
    # In production you'd add separate behaviors for /static/* with longer TTL
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization"]

      cookies {
        forward = "all"
      }
    }
  }

  # ACM certificate for HTTPS
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.lab.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name    = "${var.project_name}-distribution"
    Project = var.project_name
  }

  depends_on = [aws_acm_certificate_validation.lab]
}

# -----------------------------------------------------------------------------
# Route 53 A record — points lab.example.com at CloudFront
# Uses alias record (free) instead of CNAME (costs per query)
# -----------------------------------------------------------------------------
resource "aws_route53_record" "lab" {
  zone_id = aws_route53_zone.lab.zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = true
  }
}
