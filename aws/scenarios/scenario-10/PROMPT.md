# Scenario 12 — DynamoDB Lure: Fake Active Sessions Table

## Prompt

Create a deception scenario called `scenario-12` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: session-store-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► dynamodb:ListTables → finds prod-active-sessions
  │
  ├─► dynamodb:Scan → reads fake session records
  │     ├─► JWT tokens (look valid, realistic structure)
  │     ├─► Session IDs, user IDs, IP addresses
  │     ├─► User agent strings, login timestamps
  │     └─► Refresh tokens
  │
  └─► Attempts session hijacking with extracted tokens → triggers detection
```

### Lure Resources

- **IAM Role**: Named `session-store-readonly-role`
  - `dynamodb:ListTables`
  - `dynamodb:DescribeTable`, `dynamodb:Scan`, `dynamodb:Query`, `dynamodb:GetItem` — scoped to lure table
  - Trust: account root principal

- **DynamoDB Table**: Named `prod-active-sessions`
  - Billing mode: PAY_PER_REQUEST
  - Partition key: `session_id` (String)
  - Sort key: `user_id` (String)
  - TTL attribute: `expires_at` (set to future timestamps so records look active)
  - Encryption: default
  - Tags: `Environment=production`, `Project=auth-platform`, `ManagedBy=terraform`

### Fake Data to Seed

Seed 8-10 fake session records with:
- `session_id`: UUID format
- `user_id`: `usr_` prefixed IDs
- `jwt_token`: realistic JWT structure (header.payload.signature, base64 encoded)
- `refresh_token`: `rt_` prefixed tokens
- `ip_address`: realistic private/public IPs
- `user_agent`: real browser user agent strings
- `login_timestamp`: recent timestamps
- `expires_at`: future epoch timestamps (TTL)

### Additional Requirements

- [ ] Cost: $0.00/month
- [ ] Include `deploy.sh`, `README.md`, `fake-data/session-records.json`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-12/
├── template.yaml
├── deploy.sh
├── fake-data/
│   └── session-records.json
└── README.md
```
