# Scenario 18 — Resource Tags Breadcrumb Trail

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`resource-inventory-readonly-role` — assumable by any principal in the account.
The role grants read-only access to resource tagging APIs, allowing enumeration
of tags across the account.

The attacker uses `tag:GetResources` and service-specific tag listing calls to
discover resources with breadcrumb tags. These tags contain ARNs, S3 URIs, and
alias references that point to other resources:

- `ConfigBackup` → S3 bucket URI with IAM export
- `SecretsRef` → Secrets Manager ARN for master API keys
- `EncryptionKeyRef` → KMS key alias
- `RelatedRole` → IAM role ARN for a data admin role
- `BackupBucket` → S3 bucket URI with DynamoDB customer data backups
- `MonitoringDashboard` → CloudWatch dashboard ARN

The referenced resources may or may not exist. The point is the breadcrumb
trail — every tag lookup and every attempt to access a referenced resource
generates CloudTrail events that trigger detection.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: resource-inventory-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Uses tag:GetResources / tag:GetTagKeys to enumerate tags
  │
  ├─► Finds resources with breadcrumb tags:
  │     ├─► IAM Role tag: ConfigBackup=s3://prod-config-backup-vault/iam-export.json
  │     ├─► IAM Role tag: SecretsRef=arn:aws:secretsmanager:...:prod/master-api-keys
  │     ├─► IAM Role tag: EncryptionKeyRef=alias/prod-master-encryption
  │     ├─► SSM Param tag: RelatedRole=arn:aws:iam::...:role/prod-data-admin-role
  │     ├─► SSM Param tag: BackupBucket=s3://prod-dynamodb-backups/customer-data/
  │     └─► SSM Param tag: MonitoringDashboard=arn:aws:cloudwatch::...:dashboard/...
  │
  ├─► Follows breadcrumbs to other resources (which may or may not exist)
  │
  └─► Each lookup generates CloudTrail events → triggers detection
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `resource-inventory-readonly-role` |
| Breadcrumb Role | IAM Role | `prod-backup-automation-role` |
| Breadcrumb Parameter | SSM Parameter | `/prod/inventory/service-registry` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — 2 IAM roles + SSM parameter with breadcrumb tags |
| `deploy.sh` | One-command deploy script — creates the stack |
| `abuse.sh` | Simulates the attacker abuse chain — assumes role, enumerates tags, follows breadcrumbs |

## Security Best Practices Applied

- IAM discovery role: trust policy scoped to account root principal (not public)
- Breadcrumb IAM role: trust policy scoped to `lambda.amazonaws.com` (not assumable by attacker)
- SSM parameter: Standard tier ($0.00/month)
- No S3 buckets, no Secrets Manager secrets — referenced resources are breadcrumbs only
- Discovery role has read-only tag permissions — no write or modify access

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
  --stack-name deception-scenario-18 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-18 --region us-west-2
```
