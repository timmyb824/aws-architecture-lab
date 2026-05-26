output "rds_endpoint" {
  description = "RDS MySQL endpoint — use this in your application config"
  value       = aws_db_instance.mysql.address
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.mysql.port
}

output "rds_az" {
  description = "AZ where the RDS primary is currently running"
  value       = aws_db_instance.mysql.availability_zone
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_cluster.redis.port
}

output "db_secret_arn" {
  description = "Secrets Manager ARN — pass this to your application to retrieve credentials"
  value       = aws_secretsmanager_secret.db.arn
}
