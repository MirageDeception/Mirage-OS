output "discovery_role_arn" {
  description = "ARN of the discovery role"
  value       = aws_iam_role.customer_data_readonly_role.arn
}

output "customer_profiles_table_name" {
  description = "Name of the customer profiles table"
  value       = var.include_customer_profiles ? aws_dynamodb_table.customer_profiles_table[0].name : null
}

output "customer_profiles_table_arn" {
  description = "ARN of the customer profiles table"
  value       = var.include_customer_profiles ? aws_dynamodb_table.customer_profiles_table[0].arn : null
}

output "active_sessions_table_name" {
  description = "Name of the active sessions table"
  value       = var.include_active_sessions ? aws_dynamodb_table.active_sessions_table[0].name : null
}

output "active_sessions_table_arn" {
  description = "ARN of the active sessions table"
  value       = var.include_active_sessions ? aws_dynamodb_table.active_sessions_table[0].arn : null
}
