output "alb_dns_name" {
  description = "Hit this URL in your browser to test the app"
  value       = "http://${aws_lb.app.dns_name}"
}

output "vpc_id" {
  description = "VPC ID — useful for referencing in future labs"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}
