# Scenario 1 — Lure Terraform State Bucket

## Deception Story

An attacker who gains initial access to the AWS account discovers an IAM role named
`infra-s3-data-readonly-role` — assumable by any principal in the account. The role
grants read access to an S3 bucket called `infra-terraform-state-<account-id>`.

Inside the bucket, the attacker finds a `terraform.tfstate` file that appears to be
the state backend for core production infrastructure. The state file contains what
looks like high-value secrets:

- RDS database credentials and connection strings
- Stripe API keys (live-mode)
- IAM access keys for a deploy pipeline service account
- Redis auth tokens
- SSM parameter store values with full DB connection URIs

All credentials are fake and marked as `EXPIRED`. The realistic resource names,
endpoints, and structure are designed to waste attacker time and trigger alerts
when they attempt to use the credentials.

## Resource Chain

```
Attacker
  │
  ├─► Discovers IAM Role: infra-s3-data-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains s3:ListAllMyBuckets, s3:ListBucket, s3:GetObject
  │
  ├─► Finds S3 Bucket: infra-terraform-state-<account-id>
  │
  └─► Downloads terraform.tfstate
        │
        ├─► Fake RDS credentials (prod-core-db)
        ├─► Fake Stripe API keys (sk_live_EXPIRED_...)
        ├─► Fake IAM access keys (AKIAIOSFODNN7EXAMPLE / Inactive)
        ├─► Fake Redis auth token
        └─► Fake SSM DB connection string
```

## Security Best Practices Applied

- S3 public access is fully blocked (all four PublicAccessBlock settings enabled)
- Bucket encryption enabled (AES256 with bucket key)
- Versioning enabled on the bucket
- TLS-only access enforced via bucket policy (`aws:SecureTransport` deny)
- IAM role session duration capped at 1 hour
- Trust policy scoped to the account root only
- Least-privilege IAM policy (only the specific bucket, only read actions)
- Incomplete multipart upload cleanup lifecycle rule

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — IAM role + S3 bucket + bucket policy |
| `fake-data/terraform.tfstate` | Fake Terraform state seeded with expired placeholder credentials |
| `deploy.sh` | One-command deploy script — creates the stack and uploads the lure data |

## Deployment

### Quick deploy (recommended)

The `deploy.sh` script handles everything — resolves your account ID, deploys the
CloudFormation stack, and uploads the fake state file into the bucket:

```bash
chmod +x deploy.sh
./deploy.sh
```

By default it deploys to `us-east-1`. Override with:

```bash
AWS_DEFAULT_REGION=eu-west-1 ./deploy.sh
```

### Manual deploy

If you prefer to run the steps yourself:

```bash
# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# Deploy the stack
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name deception-scenario-1 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM

# Upload the fake state file
aws s3 cp fake-data/terraform.tfstate \
  s3://infra-terraform-state-${ACCOUNT_ID}/env/production/terraform.tfstate
```

## Customization

Edit `fake-data/terraform.tfstate` to replace placeholder credentials with your own
fake values. Keep the `EXPIRED` prefix convention so your team can quickly distinguish
lure data from real data during incident response.
