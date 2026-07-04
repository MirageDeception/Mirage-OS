# Scenario 2 Details

This deception scenario deploys a lure IAM role and AWS Secrets Manager secrets containing fake payment gateway and internal service credentials.

## Resources Created
- **IAM Role** (`payment-secrets-readonly-role`): Appears as a payment secrets reader role for backend services.
- **Secrets Manager Secrets**:
  - `prod/payment-gateway/stripe-keys`
  - `prod/payment-gateway/braintree-credentials`
  - `prod/internal-api/service-accounts`
- **Secrets Manager Policies**: Allows account root read access to these secrets.
