# Deception Scenario 13 - SQS Lure

**Description:**
Payment Events Dead Letter Queue. A FIFO queue pair (main + DLQ) seeded with fake failed payment event messages and an IAM role granting read-only access. Every queue interaction generates CloudTrail events for detection.

**Resources Created:**
1. `payment-queue-readonly-role` (IAM Role) - Grants SQS read-only access scoped to the lure queues.
2. `payment-queue-readonly-policy` (IAM Policy) - Allows SQS list queues, read attributes, and receive messages from the DLQ.
3. `prod-payment-events-dlq.fifo` (SQS Queue) - Dead letter FIFO queue for payment events.
4. `prod-payment-events.fifo` (SQS Queue) - Main FIFO queue with DLQ redrive policy pointing to the DLQ.
