output "discovery_role_arn" {
  description = "ARN of the discovery role (lambda-ops-readonly-role)"
  value       = aws_iam_role.lambda_ops_readonly_role.arn
}

output "discovery_role_name" {
  description = "Name of the discovery role"
  value       = aws_iam_role.lambda_ops_readonly_role.name
}

output "exec_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.data_sync_exec_role.arn
}

output "lambda_function_arn" {
  description = "ARN of the lure Lambda function"
  value       = aws_lambda_function.data_sync_processor.arn
}

output "lambda_function_name" {
  description = "Name of the lure Lambda function"
  value       = aws_lambda_function.data_sync_processor.function_name
}

output "s3_bucket_name" {
  description = "Name of the data sync artifacts bucket"
  value       = var.include_s3 ? aws_s3_bucket.data_sync_artifacts_bucket[0].bucket : null
}

output "secret_arn" {
  description = "ARN of the API credentials secret"
  value       = var.include_secrets_manager ? aws_secretsmanager_secret.api_credentials_secret[0].arn : null
}

output "ssm_parameter_name" {
  description = "Name of the data sync config SSM parameter"
  value       = var.include_ssm ? aws_ssm_parameter.data_sync_config_param[0].name : null
}
