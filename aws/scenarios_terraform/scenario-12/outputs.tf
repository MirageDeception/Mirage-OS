output "discovery_role_arn" {
  description = "ARN of the discovery role (alerts-readonly-role)"
  value       = aws_iam_role.alerts_readonly_role.arn
}

output "topic_arn" {
  description = "ARN of the critical alerts SNS topic"
  value       = aws_sns_topic.critical_alerts_topic.arn
}

output "decoy_resources" {
  description = "JSON array of decoy resources for EventBridge rule generation"
  value = jsonencode([
    {
      category  = "iam"
      resources = aws_iam_role.alerts_readonly_role.name
    },
    {
      category  = "sns"
      resources = aws_sns_topic.critical_alerts_topic.name
    }
  ])
}
