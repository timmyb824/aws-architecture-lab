# -----------------------------------------------------------------------------
# IAM Role — allows Config to record resource configurations
# and deliver snapshots to S3
# -----------------------------------------------------------------------------
resource "aws_iam_role" "config" {
  name = "${var.project_name}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${var.project_name}-config-role"
    Project = var.project_name
  }
}

# AWS managed policy — gives Config everything it needs to read resource configs
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Allow Config to write delivery snapshots to the CloudTrail S3 bucket
# We reuse the CloudTrail bucket to avoid creating another one
resource "aws_iam_role_policy" "config_s3" {
  name = "${var.project_name}-config-s3"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetBucketAcl"
      ]
      Resource = [
        aws_s3_bucket.cloudtrail.arn,
        "${aws_s3_bucket.cloudtrail.arn}/*"
      ]
    }]
  })
}

# -----------------------------------------------------------------------------
# Config Recorder — tells Config what to record
# record_all_supported = true captures all resource types
# include_global_resource_types = true captures IAM resources
# -----------------------------------------------------------------------------
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# -----------------------------------------------------------------------------
# Delivery Channel — where Config sends configuration snapshots
# Config requires a delivery channel before the recorder can be enabled
# -----------------------------------------------------------------------------
resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-delivery"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  depends_on = [aws_config_configuration_recorder.main]
}

# -----------------------------------------------------------------------------
# Start the recorder — separate from creating it
# This is a quirk of the AWS Config Terraform resources
# -----------------------------------------------------------------------------
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# -----------------------------------------------------------------------------
# Managed Rules — Config evaluates these against your resources continuously
# These three are the most commonly tested on SAA-C03
# -----------------------------------------------------------------------------

# Rule 1: No unrestricted SSH access (port 22 open to 0.0.0.0/0)
# One of the most common misconfigurations in real environments
resource "aws_config_config_rule" "no_unrestricted_ssh" {
  name        = "${var.project_name}-no-unrestricted-ssh"
  description = "Checks that no security groups allow unrestricted SSH access"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Project = var.project_name
  }
}

# Rule 2: S3 buckets should block public access
# Catches accidentally public buckets before they become incidents
resource "aws_config_config_rule" "s3_public_access_blocked" {
  name        = "${var.project_name}-s3-public-access-blocked"
  description = "Checks that S3 buckets have public access blocked"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Project = var.project_name
  }
}

# Rule 3: RDS instances should not be publicly accessible
# Validates our Lab 2 RDS config is correct
resource "aws_config_config_rule" "rds_not_public" {
  name        = "${var.project_name}-rds-not-public"
  description = "Checks that RDS instances are not publicly accessible"

  source {
    owner             = "AWS"
    source_identifier = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Project = var.project_name
  }
}
