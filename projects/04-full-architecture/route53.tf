
# -----------------------------------------------------------------------------
# Route 53 Health Check — monitors the CloudFront endpoint
# Checks every 30 seconds, fails after 3 consecutive failures
# In a multi-region setup this would trigger DNS failover
# For this lab it triggers an SNS alert
# -----------------------------------------------------------------------------
resource "aws_route53_health_check" "main" {
  fqdn              = local.fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name    = "${var.project_name}-health-check"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# SNS Topic for Lab 4 alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"

  tags = {
    Name    = "${var.project_name}-alarms"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarm — fires when health check fails
# Route 53 health check metrics live in us-east-1 regardless of region
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "health_check" {
  alarm_name          = "${var.project_name}-endpoint-health"
  alarm_description   = "lab.${var.domain_name} is failing health checks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.main.id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Project = var.project_name
  }
}
