# Session 1 — Build IaC for Scenarios 9, 11, 12, 13

## Context

You are building AWS CloudFormation deception scenarios. Each scenario is an internal-only
honeypot designed to detect insider threats or attackers already inside the AWS account.

## Rules (apply to ALL scenarios)

- **NO public access** — all resources are internal account-only decoys
- **Least privilege** — each role only gets the exact permissions needed for the scenario
- **NO cross-account** — no external account references
- **NO IAM users** — only IAM roles
- **NO FAKE/EXPIRED/REVOKED/REDACTED** labels in any data — everything must look legitimate
- Trust policies use `arn:aws:iam::<AccountId>:root` for discovery roles
- S3 buckets: full PublicAccessBlock (all 4 settings), AES256 encryption with BucketKey, versioning, TLS-only bucket policy
- Secrets Manager: resource policy allows read from account root only
- SSM: Standard tier unless payload requires Advanced
- Default region: `us-west-2`
- Deploy scripts: `set -euo pipefail`, colored output (CYAN for info, GREEN for ok, YELLOW for warn), comments
- Each scenario gets: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, and `fake-data/` if needed

## Scenarios to Build

### Scenario 9 — IAM Role Chain Loop
- Read `scenarios/scenario-9/PROMPT.md` for full spec
- Already has template.yaml, deploy.sh, README.md — **only needs `abuse.sh`**
- Abuse script: assume role A, read SSM, assume role B, read SSM, assume role C, read SSM, assume role A again (loop)

### Scenario 11 — DynamoDB Fake Customer Profiles
- Read `scenarios/scenario-11/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, `fake-data/customer-records.json`
- DynamoDB PAY_PER_REQUEST, partition key `customer_id`, sort key `email`
- Deploy script seeds 10-15 records via `aws dynamodb put-item` loop
- Abuse script: assume role, list tables, describe table, scan records

### Scenario 12 — DynamoDB Fake Active Sessions
- Read `scenarios/scenario-12/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, `fake-data/session-records.json`
- DynamoDB PAY_PER_REQUEST, partition key `session_id`, sort key `user_id`, TTL on `expires_at`
- Deploy script seeds 8-10 session records with realistic JWT tokens
- Abuse script: assume role, list tables, scan sessions, extract JWTs

### Scenario 13 — SQS Payment Events Dead Letter Queue
- Read `scenarios/scenario-13/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, `fake-data/payment-events.json`
- SQS FIFO queue + DLQ, SSE-SQS encryption
- Deploy script sends 5-8 fake payment event messages to the DLQ
- Abuse script: assume role, list queues, get attributes, receive messages from DLQ

## Style Reference

Look at `scenarios/scenario-6/template.yaml`, `scenarios/scenario-6/deploy.sh`, and
`scenarios/scenario-1/abuse.sh` for the established patterns.
