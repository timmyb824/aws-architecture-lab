# -----------------------------------------------------------------------------
# S3 Bucket — CloudTrail log destination
# CloudTrail needs its own bucket with a specific bucket policy
# that allows the CloudTrail service to write to it
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cloudtrail-${local.account_id}"
  force_destroy = true # allows destroy even with log files in it

  tags = {
    Name    = "${var.project_name}-cloudtrail"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Policy — required for CloudTrail to write logs
# Without this explicit policy CloudTrail will refuse to create the trail
# Note the two statements:
#   1. Allow CloudTrail to check the bucket ACL
#   2. Allow CloudTrail to write log files
# Both are required — CloudTrail checks ACL first before writing
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudTrail — management events only, multi-region
# multi_region = true means it captures events from ALL regions
# not just us-east-1 — important because some global services like
# IAM always log to us-east-1 regardless of where you're working
# include_global_service_events = true captures IAM, STS, CloudFront
# -----------------------------------------------------------------------------
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  # Log file validation — detects if log files are modified or deleted
  # Generates a digest file every hour that you can use to verify integrity
  enable_log_file_validation = true

  tags = {
    Name    = "${var.project_name}-trail"
    Project = var.project_name
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
