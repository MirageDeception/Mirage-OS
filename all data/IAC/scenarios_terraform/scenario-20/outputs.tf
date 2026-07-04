output "discovery_role_arn" {
  description = "ARN of the discovery role (infra-params-readonly-role)"
  value       = aws_iam_role.infra_params_readonly_role.arn
}

output "primary_param_arn" {
  description = "ARN of the /prod/db/primary SSM parameter"
  value       = "arn:aws:ssm:$${data.aws_region.current.name}:$${var.account_id}:parameter/prod/db/primary"
}

output "replica_param_arn" {
  description = "ARN of the /prod/db/replica SSM parameter"
  value       = "arn:aws:ssm:$${data.aws_region.current.name}:$${var.account_id}:parameter/prod/db/replica"
}

output "backup_config_param_arn" {
  description = "ARN of the /prod/db/backup-config SSM parameter"
  value       = "arn:aws:ssm:$${data.aws_region.current.name}:$${var.account_id}:parameter/prod/db/backup-config"
}

output "encryption_config_param_arn" {
  description = "ARN of the /prod/db/encryption-config SSM parameter"
  value       = "arn:aws:ssm:$${data.aws_region.current.name}:$${var.account_id}:parameter/prod/db/encryption-config"
}

output "monitoring_param_arn" {
  description = "ARN of the /prod/db/monitoring SSM parameter"
  value       = "arn:aws:ssm:$${data.aws_region.current.name}:$${var.account_id}:parameter/prod/db/monitoring"
}
