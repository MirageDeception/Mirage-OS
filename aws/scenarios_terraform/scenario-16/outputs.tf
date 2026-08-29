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
  value       = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/inventory/service-registry"
}

output "decoy_resources" {
  description = "JSON array of decoy resources for EventBridge rule generation"
  value = jsonencode([
    {
      category  = "iam"
      resources = "${aws_iam_role.resource_inventory_readonly_role.name},${aws_iam_role.backup_automation_role.name}"
    },
    {
      category  = "ssm"
      resources = aws_ssm_parameter.service_registry_param.name
    },
  ])
}
