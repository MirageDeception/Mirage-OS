output "database_endpoint" {
  description = "Production RDS PostgreSQL primary endpoint"
  value       = "prod-core-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com"
}

output "database_password" {
  description = "Production database master password"
  value       = "Pr0d#Db$M@ster!2026xKqL9"
}

output "api_gateway_url" {
  description = "Production API Gateway base URL"
  value       = "https://k7x9m2p4q1.execute-api.us-west-2.amazonaws.com/prod"
}

output "api_key" {
  description = "Production API Gateway API key"
  value       = "ak_prod_V8kN3mP7qR2wX5jL9tY4bF6hC1dA0eG"
}

output "redis_endpoint" {
  description = "Production ElastiCache Redis primary endpoint"
  value       = "prod-cache.r3k8m2.0001.usw2.cache.amazonaws.com"
}

output "redis_auth_token" {
  description = "Production Redis AUTH token"
  value       = "rT#2026pR0d!cAcHe$sEcUrE9xMkL3"
}

output "admin_dashboard_url" {
  description = "Production admin dashboard URL"
  value       = "https://admin.prod.internal.corp"
}

output "vpc_id" {
  description = "Production VPC ID"
  value       = "vpc-0a1b2c3d4e5f67890"
}

output "private_subnet_ids" {
  description = "Production private subnet IDs (comma-separated)"
  value       = "subnet-0a1b2c3d4e5f6789a,subnet-0b2c3d4e5f6789a1b"
}

output "db_security_group_id" {
  description = "Production database security group ID"
  value       = "sg-0a1b2c3d4e5f67890"
}

output "discovery_role_arn" {
  description = "ARN of the discovery role (cfn-audit-readonly-role)"
  value       = aws_iam_role.cfn_audit_readonly_role.arn
}
