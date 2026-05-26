# -----------------------------------------------------------------------------
# IAM Role — this is what the EC2 instance assumes
# The trust policy says "EC2 service is allowed to assume this role"
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ec2_instance" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "${var.project_name}-ec2-role"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Attach the AWS managed SSM policy to the role
# This gives the instance everything SSM Session Manager needs:
#   - Receive session commands
#   - Send session output back
#   - Write to CloudWatch Logs
#   - Write to S3 (for session logs if configured)
# Using a managed policy here is intentional — AWS keeps it updated
# as SSM adds new features
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# -----------------------------------------------------------------------------
# Instance Profile — the wrapper that lets EC2 use the role
# You can't attach a role directly to an EC2 instance, only a profile
# In the console these appear merged but in Terraform they're separate
# -----------------------------------------------------------------------------
resource "aws_iam_instance_profile" "ec2_instance" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_instance.name

  tags = {
    Name    = "${var.project_name}-ec2-profile"
    Project = var.project_name
  }
}
