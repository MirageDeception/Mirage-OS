output "discovery_role_arn" {
  description = "ARN of the discovery role (etl-ops-readonly-role)"
  value       = aws_iam_role.etl_ops_readonly_role.arn
}

output "exec_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.user_enrichment_exec_role.arn
}

output "lambda_function_arn" {
  description = "ARN of the lure Lambda function"
  value       = aws_lambda_function.user_data_enrichment_function.arn
}

output "dynamodb_table_arn" {
  description = "ARN of the enriched user profiles DynamoDB table"
  value       = aws_dynamodb_table.enriched_user_profiles_table.arn
}
