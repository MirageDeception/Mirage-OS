# scenario-2

Description: This deception scenario deploys a lure IAM role and AWS Secrets Manager secrets containing fake payment gateway and internal service credentials.

**Resources Deployed:**
- `payment-secrets-readonly-role` (aws_iam_role)
- `payment-secrets-readonly-policy` (aws_iam_policy)
- `prod/payment-gateway/stripe-keys` (aws_secretsmanager_secret)
- `prod/payment-gateway/braintree-credentials` (aws_secretsmanager_secret)
- `prod/internal-api/service-accounts` (aws_secretsmanager_secret)
