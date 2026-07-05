# Scenario 11 — DynamoDB Lure: Fake Customer Profiles Table

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`customer-data-readonly-role` — assumable by any principal in the account. The
role grants DynamoDB read-only access.

The attacker lists DynamoDB tables and finds `prod-customer-profiles`. Describing
the table reveals a schema with `customer_id` and `email` keys — a clear sign of
customer PII. Scanning the table returns realistic-looking customer records
containing names, emails, phone numbers, payment card tokens, account statuses,
and lifetime values.

All records are fabricated decoys. Every API call in the chain generates CloudTrail
events, giving defenders multiple detection opportunities before the attacker
realizes the data is worthless.

## Deception Chain

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
  ├─► dynamodb:DescribeTable → sees schema (customer_id, email)
  │
  ├─► dynamodb:Scan → reads fake PII records
  │     ├─► Names, emails, phone numbers
  │     ├─► Card tokens, account status
  │     └─► Lifetime value, signup dates
  │
  └─► Attempts to exfiltrate or use data → triggers detection
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `customer-data-readonly-role` |
| Customer Table | DynamoDB | `prod-customer-profiles` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — IAM role + DynamoDB table |
| `deploy.sh` | One-command deploy script — creates the stack and seeds customer records |
| `abuse.sh` | Simulates the full attacker abuse chain |
| `fake-data/customer-records.json` | 12 fake customer profile records seeded into DynamoDB |

## Security Best Practices Applied

- IAM role: trust policy scoped to account root principal only (no public access)
- IAM permissions scoped to specific DynamoDB table ARN (least privilege)
- `dynamodb:ListTables` is the only wildcard-resource permission (required by API)
- DynamoDB encryption enabled (AWS-owned key)
- Point-in-time recovery enabled (looks production-grade)
- No public endpoints or cross-account access

## Cost

$0.00/month — DynamoDB on-demand with minimal data at rest is free tier eligible.

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
  --stack-name deception-scenario-11 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset

for row in $(jq -c '.[]' fake-data/customer-records.json); do
  aws dynamodb put-item \
    --table-name prod-customer-profiles \
    --item "$row" \
    --region us-west-2
done
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-11 --region us-west-2
```
