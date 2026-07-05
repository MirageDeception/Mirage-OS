# Scenario 19 — Lambda + DynamoDB Lure: Data Pipeline with PII Table

## Prompt

Create a deception scenario called `scenario-19` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: etl-ops-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► lambda:ListFunctions → finds prod-user-data-enrichment
  │
  ├─► lambda:GetFunctionConfiguration → extracts env vars:
  │     ├─► DYNAMODB_TABLE=prod-enriched-user-profiles
  │     ├─► CLEARBIT_API_KEY=sk_prod_a1b2c3d4e5f6...
  │     └─► FULLCONTACT_API_KEY=fc_prod_7g8h9i0j...
  │
  ├─► Investigates Lambda execution role → has DynamoDB read/write
  │
  ├─► dynamodb:Scan on prod-enriched-user-profiles → reads enriched PII
  │     ├─► Names, emails, company, job title
  │     ├─► Social profiles, enrichment scores
  │     └─► Revenue estimates, tech stack data
  │
  └─► Attempts to use API keys or exfiltrate PII → triggers detection
```

### Lure Resources

- **IAM Role (Discovery)**: Named `etl-ops-readonly-role`
  - `lambda:ListFunctions`, `lambda:GetFunction`, `lambda:GetFunctionConfiguration`
  - Trust: account root principal

- **Lambda Function**: Named `prod-user-data-enrichment`
  - Runtime: python3.12, minimal inline code
  - Env vars: `DYNAMODB_TABLE`, `CLEARBIT_API_KEY`, `FULLCONTACT_API_KEY`
  - Tags: `Environment=production`, `Project=growth-platform`

- **IAM Role (Lambda Execution)**: Named `prod-user-enrichment-exec-role`
  - Trust: `lambda.amazonaws.com`
  - `dynamodb:Scan`, `dynamodb:Query`, `dynamodb:GetItem`, `dynamodb:PutItem` — scoped to lure table
  - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

- **DynamoDB Table**: Named `prod-enriched-user-profiles`
  - PAY_PER_REQUEST, partition key: `user_id`, sort key: `email`
  - Seeded with 10-15 fake enriched user records

### Fake Data to Seed

Records with: `user_id`, `email`, `full_name`, `company`, `job_title`, `linkedin_url`,
`enrichment_score`, `estimated_revenue`, `tech_stack`, `last_enriched`

### Additional Requirements

- [ ] Cost: $0.00/month (Lambda not invoked + DynamoDB on-demand minimal)
- [ ] Include `deploy.sh`, `README.md`, `fake-data/enriched-users.json`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-19/
├── template.yaml
├── deploy.sh
├── fake-data/
│   └── enriched-users.json
└── README.md
```
