# Scenario 13 — SQS Lure: Payment Events Dead Letter Queue

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`payment-queue-readonly-role` — assumable by any principal in the account. The
role grants SQS read-only access to payment-related queues.

The attacker lists SQS queues and finds `prod-payment-events.fifo` and its
dead letter queue `prod-payment-events-dlq.fifo`. Checking queue attributes
reveals messages sitting in the DLQ — failed payment events waiting to be
investigated.

Reading messages from the DLQ exposes what appear to be real failed payment
transactions containing card tokens, transaction amounts, merchant IDs,
customer IDs, and error details that reference internal service endpoints.

All data is fabricated. Every SQS API call generates CloudTrail events, and
any attempt to use the extracted payment data or probe the internal endpoints
triggers detection alerts.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: payment-queue-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► sqs:ListQueues → finds prod-payment-events.fifo and DLQ
  │
  ├─► sqs:GetQueueAttributes → sees message count in DLQ
  │
  ├─► sqs:ReceiveMessage on DLQ → reads failed payment events
  │     ├─► Card tokens, amounts, merchant IDs
  │     ├─► Customer IDs, transaction references
  │     └─► Error details with internal endpoint URLs
  │
  └─► Attempts to use payment data → triggers detection
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `payment-queue-readonly-role` |
| Main Queue | SQS FIFO | `prod-payment-events.fifo` |
| Dead Letter Queue | SQS FIFO | `prod-payment-events-dlq.fifo` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — IAM role + SQS FIFO queue + DLQ |
| `deploy.sh` | One-command deploy script — creates the stack and seeds DLQ with payment events |
| `abuse.sh` | Simulates the full attacker abuse chain |
| `fake-data/payment-events.json` | 7 fake failed payment event messages |

## Security Best Practices Applied

- IAM role: trust policy scoped to account root principal only (no public access)
- IAM permissions scoped to specific SQS queue ARNs (least privilege)
- `sqs:ReceiveMessage` only granted on the DLQ (not the main queue)
- `sqs:ListQueues` is the only wildcard-resource permission (required by API)
- Both queues: SSE-SQS encryption enabled
- FIFO queues with content-based deduplication
- No public endpoints or cross-account access

## Cost

$0.00/month — SQS free tier covers 1M requests/month.

## Deployment

### Quick deploy (recommended)

```bash
chmod +x deploy.sh
./deploy.sh
```

Override region:

```bash
AWS_DEFAULT_REGION=eu-west-1 ./deploy.sh
```

### Manual deploy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name deception-scenario-13 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset

DLQ_URL=$(aws cloudformation describe-stacks \
  --stack-name deception-scenario-13 \
  --query "Stacks[0].Outputs[?OutputKey=='DLQUrl'].OutputValue" \
  --output text)

for row in $(jq -c '.[]' fake-data/payment-events.json); do
  aws sqs send-message \
    --queue-url "${DLQ_URL}" \
    --message-body "$row" \
    --message-group-id "payment-processing" \
    --region us-west-2
done
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-13 --region us-west-2
```
