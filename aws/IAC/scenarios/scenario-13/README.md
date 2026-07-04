# Scenario 15 — CloudWatch Logs Lure: Accidentally Logged Credentials

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`log-analysis-readonly-role` — assumable by any principal in the account. The
role grants read-only access to CloudWatch Logs for a payment service log group.

The attacker describes log groups and finds `/prod/payment-service/application`.
Browsing log streams reveals recent application logs across three service
instances. Mixed among normal operational logs are entries that appear to
accidentally leak production credentials:

- A stack trace containing a full PostgreSQL connection string with password
- Debug HTTP headers exposing a Stripe live API key
- A failed authentication attempt logging the password in plaintext
- An environment variable dump showing DB credentials, JWT secret, and API keys

All credentials are honeytokens. Any attempt to use them triggers detection.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: log-analysis-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains logs:DescribeLogGroups, logs:DescribeLogStreams,
  │                    logs:GetLogEvents, logs:FilterLogEvents
  │
  ├─► Describes log groups → finds /prod/payment-service/application
  │
  ├─► Describes log streams → sees 3 recent streams:
  │     ├─► payment-processor/i-0a3b7c9d1e5f2a4b6
  │     ├─► auth-service/i-0b4c8d2e6f3a5b7c9
  │     └─► bootstrap/i-0c5d9e3f7a4b6c8d0
  │
  ├─► Reads log events → extracts credentials:
  │     ├─► DB connection string in error stack trace
  │     ├─► Stripe API key in debug HTTP headers
  │     ├─► Plaintext password in auth failure log
  │     └─► Full env var dump with secrets
  │
  └─► Attacker attempts to use credentials → triggers alerts
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `log-analysis-readonly-role` |
| Log Group | CloudWatch Logs | `/prod/payment-service/application` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — Log Group + IAM role |
| `deploy.sh` | One-command deploy script — creates the stack and seeds log entries |
| `abuse.sh` | Simulates the attacker abuse chain step by step |
| `fake-data/log-entries.json` | 14 log entries across 3 streams with mixed normal and credential-leaking logs |

## Seeded Credentials (Honeytokens)

| Type | Value | Location |
|------|-------|----------|
| PostgreSQL connection | `payments_admin:Kj8#mR2xVn5qW9tL@prod-payments-db...` | Stack trace in payment-processor stream |
| Stripe API key | `sk_live_51NxGr7eD48IqMzkXEbsjT2ze1qp8dc` | Debug HTTP headers in payment-processor stream |
| User password | `admin@acme-corp.com / P@ssw0rd#Pr0d2024` | Auth failure log in auth-service stream |
| JWT secret | `jwtS1gn1ngK3y#Pr0d2024xMz9` | Env var dump in bootstrap stream |
| Datadog API key | `dd_api_7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d` | Env var dump in bootstrap stream |

## Security Best Practices Applied

- IAM discovery role: trust policy scoped to account root principal (not public)
- Discovery role permissions scoped to specific log group ARN (except DescribeLogGroups)
- Log group: 30-day retention to limit data exposure window
- No cross-account access
- No public endpoints

## Cost

$0.00/month — free tier covers 5 GB ingestion; seeded data is minimal.

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

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-15 --region us-west-2
```
