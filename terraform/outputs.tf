# Networking
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

# Compute
output "app_instance_id" {
  description = "EC2 application instance ID"
  value       = aws_instance.app.id
}

output "app_instance_public_ip" {
  description = "Public IP of the application instance"
  value       = aws_instance.app.public_ip
}

output "app_instance_private_ip" {
  description = "Private IP of the application instance"
  value       = aws_instance.app.private_ip
}

# Load Balancer
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

# Database
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "PostgreSQL database name"
  value       = aws_db_instance.postgres.name
}
