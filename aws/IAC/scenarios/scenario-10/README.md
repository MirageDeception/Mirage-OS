# Scenario 12 — DynamoDB Lure: Fake Active Sessions Table

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`session-store-readonly-role` — assumable by any principal in the account. The
role grants DynamoDB read-only access.

The attacker lists DynamoDB tables and finds `prod-active-sessions`. Scanning
the table reveals what appear to be live user sessions with JWT tokens, refresh
tokens, IP addresses, user agent strings, and login timestamps. The TTL field
(`expires_at`) shows future timestamps, making the sessions look active.

The attacker extracts JWT tokens and attempts session hijacking — triggering
detection alerts. All tokens are fabricated decoys with realistic JWT structure
(header.payload.signature) but no valid signing key behind them.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: session-store-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role → gains DynamoDB read access
  │
  ├─► dynamodb:ListTables → finds prod-active-sessions
  │
  ├─► dynamodb:Scan → reads fake session records
  │     ├─► JWT tokens (realistic structure)
  │     ├─► Session IDs, user IDs, IP addresses
  │     ├─► User agent strings, login timestamps
  │     └─► Refresh tokens
  │
  └─► Attempts session hijacking with extracted tokens → triggers detection
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `session-store-readonly-role` |
| Sessions Table | DynamoDB | `prod-active-sessions` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — IAM role + DynamoDB table with TTL |
| `deploy.sh` | One-command deploy script — creates the stack and seeds session records |
| `abuse.sh` | Simulates the full attacker abuse chain |
| `fake-data/session-records.json` | 9 fake active session records with JWT tokens |

## Security Best Practices Applied

- IAM role: trust policy scoped to account root principal only (no public access)
- IAM permissions scoped to specific DynamoDB table ARN (least privilege)
- `dynamodb:ListTables` is the only wildcard-resource permission (required by API)
- DynamoDB encryption enabled (AWS-owned key)
- TTL enabled on `expires_at` to make sessions look active
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
  --stack-name deception-scenario-12 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset

for row in $(jq -c '.[]' fake-data/session-records.json); do
  aws dynamodb put-item \
    --table-name prod-active-sessions \
    --item "$row" \
    --region us-west-2
done
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-12 --region us-west-2
```
