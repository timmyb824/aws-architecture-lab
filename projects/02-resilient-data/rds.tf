# -----------------------------------------------------------------------------
# DB Subnet Group — tells RDS which subnets it can use
# Must span at least 2 AZs for Multi-AZ to work
# We use the private subnets from Lab 1 via remote state
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  subnet_ids  = local.private_subnet_ids
  description = "Private subnets for RDS"

  tags = {
    Name    = "${var.project_name}-db-subnet-group"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Security Group — RDS
# Only accepts MySQL traffic (3306) from the EC2 security group
# We read the EC2 SG ID from Lab 1 state — add it to Lab 1 outputs first
# -----------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow MySQL inbound from EC2 instances only"
  vpc_id      = local.vpc_id

  ingress {
    description = "MySQL from EC2"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.10.0/24", "10.0.11.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-rds-sg"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# RDS MySQL — Multi-AZ enabled
# Password comes from Secrets Manager — never in variables or state
# -----------------------------------------------------------------------------
resource "aws_db_instance" "mysql" {
  identifier        = "${var.project_name}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  # Multi-AZ — synchronous standby in second AZ
  # This is what gives us automatic failover
  multi_az = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # No public access — only reachable from within the VPC
  publicly_accessible = false

  # Automated backups — required for Multi-AZ
  # Retention period in days (0 disables backups and Multi-AZ)
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Protect against accidental deletion via terraform destroy
  # Set to false for lab so we can actually destroy it
  deletion_protection = false

  # Skip final snapshot on destroy — lab only
  # In production set this to true and name the snapshot
  skip_final_snapshot = true

  tags = {
    Name    = "${var.project_name}-mysql"
    Project = var.project_name
  }
}
