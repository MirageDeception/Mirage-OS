output "discovery_role_arn" {
  description = "ARN of the discovery role (sso-audit-readonly-role)"
  value       = aws_iam_role.sso_audit_readonly_role.arn
}

output "saml_provider_arn" {
  description = "ARN of the ProdOktaSSO SAML provider"
  value       = aws_iam_saml_provider.okta_saml_provider.arn
}

output "admin_role_arn" {
  description = "ARN of the SAML-trusted admin role"
  value       = aws_iam_role.okta_admin_role.arn
}

output "developer_role_arn" {
  description = "ARN of the SAML-trusted developer role"
  value       = aws_iam_role.okta_developer_role.arn
}

output "decoy_resources" {
  description = "JSON array of decoy resources for EventBridge rule generation"
  value = jsonencode([
    {
      category  = "iam"
      resources = "${aws_iam_role.sso_audit_readonly_role.name},${aws_iam_role.okta_admin_role.name},${aws_iam_role.okta_developer_role.name}"
    },
  ])
}
