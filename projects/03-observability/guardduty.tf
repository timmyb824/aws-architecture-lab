# -----------------------------------------------------------------------------
# GuardDuty Detector — enables threat detection for this account/region
# GuardDuty analyzes:
#   - VPC Flow Logs (network anomalies, port scanning, C2 callbacks)
#   - CloudTrail (credential abuse, impossible travel, API anomalies)
#   - DNS logs (domain generation algorithms, data exfiltration via DNS)
# AWS manages all the ML models and threat intel feeds — zero infra to run
# -----------------------------------------------------------------------------
resource "aws_guardduty_detector" "main" {
  enable = true

  tags = {
    Name    = "${var.project_name}-guardduty"
    Project = var.project_name
  }
}

# Enable S3 protection feature
resource "aws_guardduty_detector_feature" "s3_logs" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

# Enable malware protection feature
resource "aws_guardduty_detector_feature" "malware_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

# -----------------------------------------------------------------------------
# CloudWatch Event Rule — routes GuardDuty findings to SNS
# GuardDuty findings are published to EventBridge automatically
# This rule catches all findings regardless of severity and forwards them
# In production you'd filter by severity: LOW/MEDIUM/HIGH
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.project_name}-guardduty-findings"
  description = "Route GuardDuty findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })

  tags = {
    Name    = "${var.project_name}-guardduty-findings"
    Project = var.project_name
  }
}

resource "aws_cloudwatch_event_target" "guardduty_findings" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alarms.arn
}

# -----------------------------------------------------------------------------
# SNS Topic Policy — allows EventBridge to publish to the SNS topic
# Without this EventBridge can't forward GuardDuty findings to SNS
# -----------------------------------------------------------------------------
resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alarms.arn
      }
    ]
  })
}
