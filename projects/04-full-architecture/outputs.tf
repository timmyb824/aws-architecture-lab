
output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_id" {
  description = "CloudFront distribution ID — needed for cache invalidations"
  value       = aws_cloudfront_distribution.main.id
}

output "site_url" {
  description = "Public URL for the lab site"
  value       = "https://${local.fqdn}"
}

output "waf_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.main.arn
}

output "health_check_id" {
  description = "Route 53 health check ID"
  value       = aws_route53_health_check.main.id
}
