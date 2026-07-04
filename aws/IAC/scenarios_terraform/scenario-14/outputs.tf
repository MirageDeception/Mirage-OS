output "discovery_role_arn" {
  description = "ARN of the discovery role (kms-audit-readonly-role)"
  value       = aws_iam_role.kms_audit_readonly_role.arn
}

output "kms_key_arn" {
  description = "ARN of the customer data encryption KMS key"
  value       = aws_kms_key.customer_data_key.arn
}

output "kms_key_id" {
  description = "Key ID of the customer data encryption KMS key"
  value       = aws_kms_key.customer_data_key.id
}

output "kms_alias_name" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.customer_data_key_alias.name
}
