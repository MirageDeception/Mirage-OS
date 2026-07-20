output "cloudtrail_rule_arn" {
  value = aws_cloudwatch_event_rule.cloudtrail_forwarder.arn
}

output "signin_rule_arn" {
  value = aws_cloudwatch_event_rule.console_signin_forwarder.arn
}
