output "forwarding_role_arn" {
  description = "ARN of the EventBridge forwarding role. Used in monitor forwarding rules."
  value       = aws_iam_role.mirage_forwarding.arn
}

output "forwarding_role_name" {
  value = aws_iam_role.mirage_forwarding.name
}
