output "discovery_role_arn" {
  description = "ARN of the discovery role (log-analysis-readonly-role)"
  value       = aws_iam_role.log_analysis_readonly_role.arn
}

output "log_group_arn" {
  description = "ARN of the payment service log group"
  value       = aws_cloudwatch_log_group.payment_service_log_group.arn
}

output "log_group_name" {
  description = "Name of the payment service log group"
  value       = aws_cloudwatch_log_group.payment_service_log_group.name
}
