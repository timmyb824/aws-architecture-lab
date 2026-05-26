# -----------------------------------------------------------------------------
# IAM Role — allows VPC Flow Logs service to write to CloudWatch
# This is a service role, not an instance role — the principal is
# vpc-flow-logs.amazonaws.com, not ec2.amazonaws.com
# -----------------------------------------------------------------------------
resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${var.project_name}-flow-logs-role"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# IAM Policy — what the flow logs role is allowed to do
# Scoped to only CloudWatch Logs operations it actually needs
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group — where flow log records land
# Retention set to 14 days — flow logs get voluminous fast
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.project_name}"
  retention_in_days = var.flow_log_retention_days

  tags = {
    Name    = "${var.project_name}-flow-logs"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# VPC Flow Log — attaches to the Lab 1 VPC
# ALL traffic = accepted + rejected, giving full visibility
# -----------------------------------------------------------------------------
resource "aws_flow_log" "main" {
  vpc_id          = local.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = {
    Name    = "${var.project_name}-flow-log"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Metric Filter — watches for REJECTED traffic in flow logs
# This turns log data into a CloudWatch metric we can alarm on
# Pattern matches flow log records where action field = REJECT
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "rejected_traffic" {
  name           = "${var.project_name}-rejected-traffic"
  log_group_name = aws_cloudwatch_log_group.flow_logs.name

  # Flow log format: version account-id interface-id srcaddr dstaddr
  #                  srcport dstport protocol packets bytes action log-status
  # [action=REJECT] matches the action field
  pattern = "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action=REJECT, flowlogstatus]"

  metric_transformation {
    name      = "RejectedConnections"
    namespace = "ArchLab/VPC"
    value     = "1"
  }
}

# -----------------------------------------------------------------------------
# Alarm — fires when rejected connection count spikes
# A sudden spike in rejected traffic often means a misconfigured security
# group, a failing service, or someone probing your infrastructure
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rejected_traffic" {
  alarm_name          = "${var.project_name}-rejected-traffic-spike"
  alarm_description   = "Spike in VPC rejected traffic — possible misconfiguration or probe"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RejectedConnections"
  namespace           = "ArchLab/VPC"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# SNS Topic for Lab 3 alarms
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"

  tags = {
    Name    = "${var.project_name}-alarms"
    Project = var.project_name
  }
}
