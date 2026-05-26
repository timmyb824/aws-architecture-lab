
# -----------------------------------------------------------------------------
# Scale-Out Policy — adds instances when CPU is high
# Target tracking is simpler than step scaling for most use cases —
# AWS automatically calculates how many instances to add/remove
# -----------------------------------------------------------------------------
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-scale-out"
  autoscaling_group_name = "arch-lab-01-asg"
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300 # seconds before another scale-out can happen
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-scale-in"
  autoscaling_group_name = "arch-lab-01-asg"
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms — trigger the scaling policies
# High CPU → scale out, Low CPU → scale in
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cpu_scale_out" {
  alarm_name          = "${var.project_name}-cpu-scale-out"
  alarm_description   = "Scale out when CPU exceeds ${var.cpu_scale_out_threshold}% for 3 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_scale_out_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = "arch-lab-01-asg"
  }

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_scale_in" {
  alarm_name          = "${var.project_name}-cpu-scale-in"
  alarm_description   = "Scale in when CPU below ${var.cpu_scale_in_threshold}% for 10 minutes"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 10
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_scale_in_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = "arch-lab-01-asg"
  }

  alarm_actions = [aws_autoscaling_policy.scale_in.arn]

  tags = {
    Project = var.project_name
  }
}
