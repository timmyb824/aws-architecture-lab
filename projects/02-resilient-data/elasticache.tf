# -----------------------------------------------------------------------------
# ElastiCache Subnet Group — same pattern as RDS subnet group
# Must span multiple AZs, uses same private subnets as RDS
# -----------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-cache-subnet-group"
  subnet_ids  = local.private_subnet_ids
  description = "Private subnets for ElastiCache"

  tags = {
    Name    = "${var.project_name}-cache-subnet-group"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Security Group — ElastiCache
# Only accepts Redis traffic (6379) from private subnet CIDRs
# Same pattern as RDS — never reachable from internet
# -----------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Allow Redis inbound from EC2 instances only"
  vpc_id      = local.vpc_id

  ingress {
    description = "Redis from EC2"
    from_port   = 6379
    to_port     = 6379
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
    Name    = "${var.project_name}-redis-sg"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# ElastiCache Cluster — Redis
# Single node for lab simplicity
# In production you'd use aws_elasticache_replication_group for Multi-AZ Redis
# -----------------------------------------------------------------------------
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = var.cache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # Maintenance window — off-peak hours
  maintenance_window = "sun:05:00-sun:06:00"

  tags = {
    Name    = "${var.project_name}-redis"
    Project = var.project_name
  }
}
