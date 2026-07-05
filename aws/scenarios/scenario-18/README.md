# Scenario 20 — SSM Parameter Cross-Reference Chain

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`infra-params-readonly-role` — assumable by any principal in the account. The
role grants read-only access to SSM parameters under `/prod/db/*`.

The attacker uses `ssm:DescribeParameters` to discover a hierarchy of five
database-related parameters. Reading the first parameter (`/prod/db/primary`)
reveals database connection credentials and a `see_also` field pointing to
`/prod/db/replica`. Each subsequent parameter contains more credentials and
another `see_also` pointer, creating a breadcrumb chain:

1. `/prod/db/primary` — Primary DB host, username, password → see_also: `/prod/db/replica`
2. `/prod/db/replica` — Replica endpoints, readonly credentials → see_also: `/prod/db/backup-config`
3. `/prod/db/backup-config` — S3 backup bucket, KMS key ARN → see_also: `/prod/db/encryption-config`
4. `/prod/db/encryption-config` — KMS key details, SSL cert ARN → see_also: `/prod/db/monitoring`
5. `/prod/db/monitoring` — Datadog API key, PagerDuty key, Slack webhook (end of chain)

The attacker is compelled to follow the entire chain, generating 5+ CloudTrail
`GetParameter` events that trigger detection.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: infra-params-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► ssm:DescribeParameters → finds /prod/db/* hierarchy
  │
  ├─► /prod/db/primary → credentials + see_also → /prod/db/replica
  │
  ├─► /prod/db/replica → credentials + see_also → /prod/db/backup-config
  │
  ├─► /prod/db/backup-config → S3 bucket + see_also → /prod/db/encryption-config
  │
  ├─► /prod/db/encryption-config → KMS key + see_also → /prod/db/monitoring
  │
  ├─► /prod/db/monitoring → Datadog/PagerDuty keys + webhook (end of chain)
  │
  └─► Each parameter read generates a CloudTrail event → triggers detection
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `infra-params-readonly-role` |
| Chain Link 1 | SSM Parameter | `/prod/db/primary` |
| Chain Link 2 | SSM Parameter | `/prod/db/replica` |
| Chain Link 3 | SSM Parameter | `/prod/db/backup-config` |
| Chain Link 4 | SSM Parameter | `/prod/db/encryption-config` |
| Chain Link 5 | SSM Parameter | `/prod/db/monitoring` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — IAM role + 5 SSM parameters |
| `deploy.sh` | One-command deploy script — creates the stack and seeds all parameters |
| `abuse.sh` | Simulates the attacker abuse chain — follows the see_also breadcrumb chain |
| `fake-data/db-primary.json` | Primary DB connection config with credentials |
| `fake-data/db-replica.json` | Replica DB endpoint config with credentials |
| `fake-data/db-backup-config.json` | Backup S3 bucket and KMS key config |
| `fake-data/db-encryption-config.json` | KMS key ARN and SSL certificate config |
| `fake-data/db-monitoring.json` | Datadog, PagerDuty, and Slack integration keys |

## Security Best Practices Applied

- IAM discovery role: trust policy scoped to account root principal (not public)
- SSM parameter read permissions scoped to `/prod/db/*` path only
- All SSM parameters use Standard tier ($0.00/month)
- No secrets in Secrets Manager — all data in SSM for simplicity
- Discovery role has no write permissions

## Cost

$0.00/month — IAM roles and SSM Standard parameters are free.

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
  --stack-name deception-scenario-20 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset

# Seed each parameter
for param in primary replica backup-config encryption-config monitoring; do
  aws ssm put-parameter \
    --name "/prod/db/${param}" \
    --value "file://fake-data/db-${param}.json" \
    --type String \
    --overwrite \
    --region us-west-2
done
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-20 --region us-west-2
```
