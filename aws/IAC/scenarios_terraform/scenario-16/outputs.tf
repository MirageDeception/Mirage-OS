output "discovery_role_arn" {
  description = "ARN of the discovery role (resource-inventory-readonly-role)"
  value       = aws_iam_role.resource_inventory_readonly_role.arn
}

output "breadcrumb_role_arn" {
  description = "ARN of the breadcrumb IAM role (prod-backup-automation-role)"
  value       = aws_iam_role.backup_automation_role.arn
}

output "ssm_parameter_arn" {
  description = "ARN of the breadcrumb SSM parameter"
  value       = "arn:aws:ssm:$${data.aws_region.current.name}:$${var.account_id}:parameter/prod/inventory/service-registry"
}
