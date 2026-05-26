
output "cloudtrail_bucket" {
  description = "S3 bucket storing CloudTrail and Config logs"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_arn" {
  description = "CloudTrail trail ARN"
  value       = aws_cloudtrail.main.arn
}

output "flow_log_group" {
  description = "CloudWatch Log Group containing VPC flow logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID — needed if you want to add findings filters"
  value       = aws_guardduty_detector.main.id
}
