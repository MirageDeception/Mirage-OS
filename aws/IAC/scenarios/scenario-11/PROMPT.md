# Scenario 13 — SQS Lure: Payment Events Dead Letter Queue

## Prompt

Create a deception scenario called `scenario-13` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: payment-queue-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► sqs:ListQueues → finds prod-payment-events.fifo and its DLQ
  │
  ├─► sqs:GetQueueAttributes → sees message count in DLQ
  │
  ├─► sqs:ReceiveMessage on DLQ → reads failed payment event messages
  │     ├─► Card tokens, amounts, merchant IDs
  │     ├─► Customer IDs, transaction references
  │     └─► Error details with internal endpoint URLs
  │
  └─► Attempts to use payment data → triggers detection
```

### Lure Resources

- **IAM Role**: Named `payment-queue-readonly-role`
  - `sqs:ListQueues`
  - `sqs:GetQueueAttributes`, `sqs:GetQueueUrl` — scoped to lure queues
  - `sqs:ReceiveMessage` — scoped to DLQ only
  - Trust: account root principal

- **SQS FIFO Queue**: Named `prod-payment-events.fifo`
  - Content-based deduplication enabled
  - Encryption: SSE-SQS
  - Dead letter queue configured with maxReceiveCount: 3
  - Tags: `Environment=production`, `Project=payment-platform`

- **SQS FIFO DLQ**: Named `prod-payment-events-dlq.fifo`
  - Seeded with 5-8 fake failed payment event messages
  - Encryption: SSE-SQS
  - Tags: `Environment=production`, `Project=payment-platform`

### Fake Data to Seed (messages sent to DLQ via deploy script)

Each message is a JSON payment event with:
- `transaction_id`, `customer_id`, `merchant_id`
- `card_token` (tok_ prefixed), `amount`, `currency`
- `error_code`, `error_message` (referencing internal endpoints)
- `payment_gateway_response` with internal URLs
- `MessageGroupId`: `payment-processing`

### Additional Requirements

- [ ] Cost: $0.00/month (SQS free tier: 1M requests)
- [ ] Deploy script sends fake messages to the DLQ
- [ ] Include `deploy.sh`, `README.md`, `fake-data/payment-events.json`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-13/
├── template.yaml
├── deploy.sh
├── fake-data/
│   └── payment-events.json
└── README.md
```
