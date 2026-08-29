# scenario-11

Description: Payment Events Dead Letter Queue. A FIFO queue pair (main + DLQ) seeded with fake failed payment event messages and an IAM role granting read-only access. Every queue interaction generates CloudTrail events for detection.

**Resources Deployed:**
- `payment-queue-readonly-role` (aws_iam_role)
- `payment-queue-readonly-policy` (aws_iam_policy)
- `prod-payment-events-dlq.fifo` (aws_sqs_queue)
- `prod-payment-events.fifo` (aws_sqs_queue)
