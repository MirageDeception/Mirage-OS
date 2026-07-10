output "deployment_role_arn" {
  description = "ARN of the mirage deployment role. Pass to `mirage roles import --role-arn`."
  value       = aws_iam_role.mirage_deployment.arn
}

output "deployment_role_name" {
  value = aws_iam_role.mirage_deployment.name
}

output "external_id" {
  description = "The ExternalId that hub must use when assuming this role."
  value       = var.external_id
}
