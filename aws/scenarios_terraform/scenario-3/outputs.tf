output "role_arn" {
  description = "ARN of the lure infra config role"
  value       = aws_iam_role.infra_config_readonly_role.arn
}

output "parameter_names" {
  description = "List of lure SSM parameter names"
  value       = join(", ", [
    aws_ssm_parameter.database_master_credentials.name,
    aws_ssm_parameter.github_deploy_token.name,
    aws_ssm_parameter.datadog_api_keys.name,
    aws_ssm_parameter.vpn_admin_credentials.name,
    aws_ssm_parameter.eks_kubeconfig.name
  ])
}

output "decoy_resources" {
  description = "A JSON mapping of decoy resources to their service category"
  value = jsonencode([
    {
      category  = "iam"
      resources = aws_iam_role.infra_config_readonly_role.name
    },
    {
      category  = "ssm"
      resources = "${aws_ssm_parameter.database_master_credentials.name},${aws_ssm_parameter.github_deploy_token.name},${aws_ssm_parameter.datadog_api_keys.name},${aws_ssm_parameter.vpn_admin_credentials.name},${aws_ssm_parameter.eks_kubeconfig.name}"
    }
  ])
}
