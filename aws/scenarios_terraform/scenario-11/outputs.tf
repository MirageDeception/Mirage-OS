output "discovery_role_arn" {
  description = "ARN of the discovery role (payment-queue-readonly-role)"
  value       = aws_iam_role.payment_queue_readonly_role.arn
}

output "main_queue_arn" {
  description = "ARN of the main payment events FIFO queue"
  value       = aws_sqs_queue.payment_events_queue.arn
}

output "main_queue_url" {
  description = "URL of the main payment events FIFO queue"
  value       = aws_sqs_queue.payment_events_queue.id
}

output "dlq_arn" {
  description = "ARN of the payment events dead letter queue"
  value       = aws_sqs_queue.payment_events_dlq.arn
}

output "dlq_url" {
  description = "URL of the payment events dead letter queue"
  value       = aws_sqs_queue.payment_events_dlq.id
}

output "decoy_resources" {
  description = "JSON array of decoy resources for EventBridge rule generation"
  value = jsonencode([
    {
      category  = "iam"
      resources = aws_iam_role.payment_queue_readonly_role.name
    },
    {
      category  = "sqs"
      resources = "${aws_sqs_queue.payment_events_queue.name},${aws_sqs_queue.payment_events_dlq.name}"
    },
  ])
}
