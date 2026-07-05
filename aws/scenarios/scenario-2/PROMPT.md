# Scenario 2 — Secrets Manager Lure: Payment Gateway Credentials

## Prompt

Create a deception scenario called `scenario-2` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or secret content. All credentials must look legitimate and usable to
maximize attacker engagement.

### Lure Resources

- **IAM Role**: Named `payment-secrets-readonly-role` with permissions:
  - `secretsmanager:ListSecrets`
  - `secretsmanager:GetSecretValue` condition on the specific resource only
  - `secretsmanager:DescribeSecret` condition on the specific resource only
  - `sts:AssumeRole` in trust policy by anyone in this account (root principal)

- **Secrets Manager Secret 1**: Named `prod/payment-gateway/stripe-keys`
  - Contains fake Stripe live-mode secret key, publishable key, and webhook signing secret
  - All prefixed with `EXPIRED` or `REVOKED`

- **Secrets Manager Secret 2**: Named `prod/payment-gateway/braintree-credentials`
  - Contains fake Braintree merchant ID, public key, private key, and tokenization key
  - All marked as expired/revoked

- **Secrets Manager Secret 3**: Named `prod/internal-api/service-accounts`
  - Contains fake internal service account credentials: API keys, JWT signing secrets, OAuth client secrets
  - Looks like a shared credential store for microservice-to-microservice auth

### Trust / Access Model

- Role assumable by any principal in this account via `sts:AssumeRole` (root principal in trust policy)
- Secrets have resource policies allowing read from account root principal (not public)
- Role policy scoped only to the three lure secrets (least privilege)

### Fake Data to Seed

- `fake-data/stripe-keys.json` — Fake Stripe credentials:
  ```json
  {
    "stripe_secret_key": "sk_live51HzGr4eC39HqLyjWDarjtT1zdp7dc",
    "stripe_publishable_key": "pk_liveTYooMQauvdEDq54NiTphI7jx",
    "stripe_webhook_secret": "whsect4hG7kL2mN9pQ1rS3uV5wX8y",
    "environment": "production",
    "last_rotated": "2024-08-15T00:00:00Z"
  }
  ```

- `fake-data/braintree-credentials.json` — Fake Braintree credentials:
  ```json
  {
    "merchant_id": "prod_merchant_7x9k2m",
    "public_key": "braintree_pub_3n8f5h2j",
    "private_key": "braintree_priv_9w4r7t1y6u3i8o5p",
    "tokenization_key": "productionf47ac10b58cc4372a5670e02b2c3d479",
    "environment": "production",
    "gateway_endpoint": "https://payments.prod.internal.corp/api/v2"
  }
  ```

- `fake-data/service-accounts.json` — Fake internal service credentials:
  ```json
  {
    "order_service": {
      "api_key": "EXPIRED-ak-order-svc-a1b2c3d4e5f6a7b8c9d0",
      "jwt_signing_secret": "EXPIRED-jwt-xP9mK2vL5nQ8wR1tY4uJ7hG3fD6sA0"
    },
    "inventory_service": {
      "api_key": "EXPIRED-ak-inventory-svc-f6e5d4c3b2a1f0e9d8c7",
      "oauth_client_id": "inventory-svc-prod-client",
      "oauth_client_secret": "EXPIRED-oauth-7kL2mN9pQ1rS3uV5wX8yZ0"
    },
    "notification_service": {
      "api_key": "EXPIRED-ak-notif-svc-b8c9d0a1b2c3d4e5f6a7",
      "sendgrid_api_key": "SG.EXPIRED.xK9mP2vL5nQ8wR1tY4uJ7hG3fD6sA0bE"
    }
  }
  ```

### Resource Naming Style

- Secret names follow `prod/<service-domain>/<credential-type>` convention
- Role name suggests read-only payment access
- Tags: `Environment=production`, `Project=payment-platform`, `ManagedBy=terraform`, `CostCenter=CC-7192`

### Additional Requirements

- [ ] All resources must follow security best practices (encryption with AWS-managed KMS key, no public access, least privilege)
- [ ] Secrets should have realistic descriptions and rotation configuration (disabled but configured to look real)
- [ ] Include a `deploy.sh` bash script that deploys the stack and creates all secret values — with comments
- [ ] Include a `README.md` explaining the deception story, resource chain, file listing, and deployment steps
- [ ] All secrets/credentials must be completely fake placeholder data (use `EXPIRED` or `REVOKED` prefix)
- [ ] Place everything under `scenarios/scenario-2/`

### Output Structure

```
scenarios/scenario-2/
├── template.yaml
├── deploy.sh
├── fake-data/
│   ├── stripe-keys.json
│   ├── braintree-credentials.json
│   └── service-accounts.json
└── README.md
```
