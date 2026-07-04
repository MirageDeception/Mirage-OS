# Scenario 11 — DynamoDB Lure: Fake Customer Profiles Table

## Prompt

Create a deception scenario called `scenario-11` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: customer-data-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role → gains DynamoDB read access
  │
  ├─► dynamodb:ListTables → finds prod-customer-profiles
  │
  ├─► dynamodb:DescribeTable → sees schema (customer_id, email, etc.)
  │
  ├─► dynamodb:Scan or dynamodb:Query → reads fake PII records
  │     ├─► Names, emails, phone numbers
  │     ├─► Card tokens, account status
  │     └─► Lifetime value, signup dates
  │
  └─► Attempts to exfiltrate or use data → triggers detection
```

### Lure Resources

- **IAM Role**: Named `customer-data-readonly-role`
  - `dynamodb:ListTables`
  - `dynamodb:DescribeTable` — scoped to the lure table
  - `dynamodb:Scan`, `dynamodb:Query`, `dynamodb:GetItem` — scoped to the lure table
  - Trust: account root principal

- **DynamoDB Table**: Named `prod-customer-profiles`
  - Billing mode: PAY_PER_REQUEST (on-demand, no cost at rest)
  - Partition key: `customer_id` (String)
  - Sort key: `email` (String)
  - Encryption: AWS-owned key (default)
  - Point-in-time recovery: enabled (looks real)
  - Tags: `Environment=production`, `Project=customer-platform`, `ManagedBy=terraform`

### Fake Data to Seed (via deploy script using `aws dynamodb put-item`)

Seed 10-15 fake customer records with fields:
- `customer_id`: `CUST-00001` through `CUST-00015`
- `email`: `[email]` placeholder
- `full_name`: `[name]` placeholder
- `phone`: `[phone_number]` placeholder
- `card_token`: realistic-looking token (e.g., `tok_1NxPr0dC4rd...`)
- `account_status`: `active` / `suspended`
- `lifetime_value`: random dollar amounts
- `signup_date`: realistic dates
- `last_login`: recent dates

### Additional Requirements

- [ ] DynamoDB on-demand = $0.00 at rest with minimal data
- [ ] Deploy script seeds records using `aws dynamodb put-item` in a loop
- [ ] Include `deploy.sh`, `README.md`, `fake-data/customer-records.json`
- [ ] Cost: $0.00/month
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-11/
├── template.yaml
├── deploy.sh
├── fake-data/
│   └── customer-records.json
└── README.md
```
