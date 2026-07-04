# Scenario 15 — CloudWatch Logs Lure: Accidentally Logged Credentials

## Prompt

Create a deception scenario called `scenario-15` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: log-analysis-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► logs:DescribeLogGroups → finds /prod/payment-service/application
  │
  ├─► logs:DescribeLogStreams → sees recent log streams
  │
  ├─► logs:GetLogEvents / logs:FilterLogEvents → reads log entries
  │     ├─► Stack trace with DB connection string in error message
  │     ├─► Debug log accidentally printing API key in request header
  │     ├─► Failed auth attempt logging the password in plaintext
  │     └─► Environment dump showing all env vars including secrets
  │
  └─► Attempts to use extracted credentials → triggers detection
```

### Lure Resources

- **IAM Role**: Named `log-analysis-readonly-role`
  - `logs:DescribeLogGroups`, `logs:DescribeLogStreams`
  - `logs:GetLogEvents`, `logs:FilterLogEvents` — scoped to lure log group
  - Trust: account root principal

- **CloudWatch Log Group**: Named `/prod/payment-service/application`
  - Retention: 30 days
  - Tags: `Environment=production`, `Project=payment-platform`

### Fake Data to Seed (log entries via deploy script using `aws logs put-log-events`)

Seed 10-15 fake log entries across 2-3 log streams, including:

- **Error with DB connection string**:
  `2024-11-15T02:14:33Z ERROR [PaymentProcessor] Connection failed: postgresql://payments_admin:Kj8#mR2xVn5qW9tL@prod-payments-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com:5432/payments_prod`

- **Debug log with API key**:
  `2024-11-15T02:14:35Z DEBUG [HttpClient] Request headers: {Authorization: Bearer sk_live_51NxGr7eD48IqMzkXEbsjT2ze1qp8dc, Content-Type: application/json}`

- **Failed auth with password**:
  `2024-11-15T02:14:40Z WARN [AuthService] Authentication failed for user admin@acme-corp.com with password P@ssw0rd#Pr0d2024 - invalid credentials`

- **Environment variable dump**:
  `2024-11-15T02:14:45Z INFO [Bootstrap] Environment: DB_HOST=prod-payments-db..., STRIPE_KEY=sk_live_..., JWT_SECRET=jwtS1gn1ng...`

### Additional Requirements

- [ ] Cost: $0.00/month (free tier: 5 GB ingestion, minimal data)
- [ ] Log entries should look like real application logs with timestamps, levels, class names
- [ ] Mix normal-looking logs with the credential-leaking ones
- [ ] Include `deploy.sh`, `README.md`, `fake-data/log-entries.json`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-15/
├── template.yaml
├── deploy.sh
├── fake-data/
│   └── log-entries.json
└── README.md
```
