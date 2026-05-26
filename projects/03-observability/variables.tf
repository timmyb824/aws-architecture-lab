variable "aws_region" {
  description = "AWS region for all resources"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Used to namespace all resource names and tags"
  default     = "arch-lab-03"
}

variable "log_retention_days" {
  description = "How long to keep logs in CloudWatch — cost control"
  default     = 7
}

variable "flow_log_retention_days" {
  description = "VPC Flow Log retention — separate from app logs"
  default     = 14
}
