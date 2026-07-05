# Scenario 2 — Secrets Manager Lure: Payment Gateway Credentials

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`payment-secrets-readonly-role` — assumable by any principal in the account.
The role grants the ability to list all secrets and read three specific
Secrets Manager secrets.

The attacker finds secrets that appear to be live production credentials for:

- Stripe payment gateway (secret key, publishable key, webhook secret)
- Braintree payment fallback processor (merchant ID, keys, tokenization key)
- Internal microservice auth (API keys, JWT signing secrets, OAuth client secrets)

All values look legitimate and usable. The realistic naming, structure, and
credential formats are designed to lure the attacker into attempting to use
them — triggering detection alerts.

## Resource Chain

```
Attacker
  │
  ├─► Discovers IAM Role: payment-secrets-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains secretsmanager:ListSecrets + scoped Get/Describe
  │
  ├─► Lists secrets ─► finds payment-related secret names
  │
  └─► Reads secret values
        │
        ├─► prod/payment-gateway/stripe-keys
        │     └─► sk_live_..., pk_live_..., whsec_...
        │
        ├─► prod/payment-gateway/braintree-credentials
        │     └─► merchant_id, public_key, private_key, tokenization_key
        │
        └─► prod/internal-api/service-accounts
              └─► order_service, inventory_service, notification_service creds
```

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — IAM role + 3 Secrets Manager secrets + resource policies |
| `deploy.sh` | One-command deploy script — creates the stack and seeds all secret values |
| `fake-data/stripe-keys.json` | Fake Stripe live-mode API credentials |
| `fake-data/braintree-credentials.json` | Fake Braintree merchant credentials |
| `fake-data/service-accounts.json` | Fake internal service-to-service auth credentials |

## Security Best Practices Applied

- Secrets encrypted with AWS-managed KMS key (default)
- Resource policies on each secret scoped to account root only (not public)
- IAM role `GetSecretValue` and `DescribeSecret` scoped to the three specific secret ARNs only
- `ListSecrets` is the only broad permission (required for discovery — part of the lure)
- IAM role session duration capped at 1 hour
- Trust policy scoped to account root principal only

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
  --stack-name deception-scenario-2 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM

aws secretsmanager put-secret-value \
  --secret-id prod/payment-gateway/stripe-keys \
  --secret-string file://fake-data/stripe-keys.json

aws secretsmanager put-secret-value \
  --secret-id prod/payment-gateway/braintree-credentials \
  --secret-string file://fake-data/braintree-credentials.json

aws secretsmanager put-secret-value \
  --secret-id prod/internal-api/service-accounts \
  --secret-string file://fake-data/service-accounts.json
```

## Customization

Edit the JSON files in `fake-data/` to replace credentials with your own
fake values. Keep the format realistic — match real provider key patterns
(e.g., `sk_live_` prefix for Stripe, `SG.` prefix for SendGrid).
