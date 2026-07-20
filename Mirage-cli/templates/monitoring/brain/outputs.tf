output "event_bus_arn" {
  value = aws_cloudwatch_event_bus.deception_bus.arn
}

output "event_bus_name" {
  value = aws_cloudwatch_event_bus.deception_bus.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "lambda_arn" {
  value = aws_lambda_function.brain.arn
}
