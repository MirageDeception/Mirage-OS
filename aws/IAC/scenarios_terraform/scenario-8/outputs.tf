output "auth_role_arn" {
  description = "ARN of the auth service role (Role A — entry point)"
  value       = aws_iam_role.microservice_auth_role.arn
}

output "data_role_arn" {
  description = "ARN of the data layer service role (Role B)"
  value       = aws_iam_role.microservice_data_role.arn
}

output "admin_role_arn" {
  description = "ARN of the admin console service role (Role C)"
  value       = aws_iam_role.microservice_admin_role.arn
}

output "oidc_config_param_arn" {
  description = "ARN of the OIDC config SSM parameter"
  value       = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/auth/oidc-config"
}

output "lake_credentials_param_arn" {
  description = "ARN of the data lake credentials SSM parameter"
  value       = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/data/lake-credentials"
}

output "console_credentials_param_arn" {
  description = "ARN of the admin console credentials SSM parameter"
  value       = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/admin/console-credentials"
}
