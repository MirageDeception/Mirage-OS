output "mode" {
  description = "Deployment mode (standalone or linked to scenario-6)"
  value       = var.link_to_scenario_6 ? "linked-to-scenario-6" : "standalone"
}

output "discovery_role_arn" {
  description = "ARN of the standalone discovery role"
  value       = var.link_to_scenario_6 ? null : aws_iam_role.standalone_discovery_role[0].arn
}

output "lambda_function_arn" {
  description = "ARN of the standalone Lambda function"
  value       = var.link_to_scenario_6 ? null : aws_lambda_function.standalone_lambda[0].arn
}

output "decoy_resources" {
  description = "JSON array of decoy resources for EventBridge rule generation"
  value = jsonencode([
    {
      category  = "iam"
      resources = var.link_to_scenario_6 ? "" : aws_iam_role.standalone_discovery_role[0].name
    },
    {
      category  = "lambda"
      resources = var.link_to_scenario_6 ? "" : aws_lambda_function.standalone_lambda[0].function_name
    },
  ])
}
