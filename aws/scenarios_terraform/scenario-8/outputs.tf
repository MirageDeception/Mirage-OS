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

output "decoy_resources" {
  description = "JSON array of decoy resources for EventBridge rule generation"
  value = jsonencode([
    {
      category  = "iam"
      resources = "${aws_iam_role.microservice_auth_role.name},${aws_iam_role.microservice_data_role.name},${aws_iam_role.microservice_admin_role.name}"
    },
    {
      category  = "ssm"
      resources = "${aws_ssm_parameter.oidc_config_param.name},${aws_ssm_parameter.lake_credentials_param.name},${aws_ssm_parameter.console_credentials_param.name}"
    },
  ])
}
