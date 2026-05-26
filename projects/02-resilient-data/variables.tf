variable "aws_region" {
  description = "AWS region for all resources"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Used to namespace all resource names and tags"
  default     = "arch-lab-02"
}

variable "db_name" {
  description = "Name of the MySQL database to create"
  default     = "archlab"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  default     = "admin"
}

variable "db_instance_class" {
  description = "RDS instance type"
  default     = "db.t3.micro"
}

variable "cache_node_type" {
  description = "ElastiCache node type"
  default     = "cache.t3.micro"
}
