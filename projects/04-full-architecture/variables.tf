
variable "aws_region" {
  description = "Primary AWS region"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Used to namespace all resource names and tags"
  default     = "arch-lab-04"
}

variable "domain_name" {
  description = "Root domain for the lab subdomain"
}

variable "subdomain" {
  description = "Subdomain to create under domain_name"
  default     = "lab"
}

variable "cpu_scale_out_threshold" {
  description = "CPU % that triggers scale-out"
  default     = 60
}

variable "cpu_scale_in_threshold" {
  description = "CPU % that triggers scale-in"
  default     = 30
}

variable "monthly_budget_usd" {
  description = "Monthly budget alert threshold in USD"
  default     = 50
}

variable "subscriber_email" {
  description = "Email address to receive budget alerts"
}

