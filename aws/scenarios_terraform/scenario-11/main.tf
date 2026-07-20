# ---------------------------------------------------------------
# IAM Role — payment-queue-readonly-role
# ---------------------------------------------------------------
resource "aws_iam_role" "payment_queue_readonly_role" {
  name                 = var.role_readonly
  description          = "Read-only access to payment event queues for operations team"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "production"
    Project     = "payment-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-5320"
  }
}

resource "aws_iam_role_policy_attachment" "payment_queue_readonly_policy_attachment" {
  role       = aws_iam_role.payment_queue_readonly_role.name
  policy_arn = aws_iam_policy.payment_queue_readonly_policy.arn
}

resource "aws_iam_policy" "payment_queue_readonly_policy" {
  name = "payment-queue-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSListQueues"
        Effect = "Allow"
        Action = [
          "sqs:ListQueues"
        ]
        Resource = "*"
      },
      {
        Sid    = "SQSReadQueueAttributes"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.payment_events_queue.arn,
          aws_sqs_queue.payment_events_dlq.arn
        ]
      },
      {
        Sid    = "SQSReceiveDLQ"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.payment_events_dlq.arn
      }
    ]
  })
}

# ---------------------------------------------------------------
# SQS FIFO DLQ — prod-payment-events-dlq.fifo
# ---------------------------------------------------------------
resource "aws_sqs_queue" "payment_events_dlq" {
  name                        = "${var.queue_dlq}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  sqs_managed_sse_enabled     = true
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 30

  tags = {
    Environment = "production"
    Project     = "payment-platform"
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------
# SQS FIFO Queue — prod-payment-events.fifo
# ---------------------------------------------------------------
resource "aws_sqs_queue" "payment_events_queue" {
  name                        = "${var.queue_main}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  sqs_managed_sse_enabled     = true
  message_retention_seconds   = 345600
  visibility_timeout_seconds  = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.payment_events_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Environment = "production"
    Project     = "payment-platform"
    ManagedBy   = "terraform"
  }
}
