# Scenario 2 — Attack Path & Cost Estimation

## Attack Path

```
1. Attacker enumerates IAM roles in the account
2. Discovers: payment-secrets-readonly-role (assumable by any account principal)
3. Assumes the role via sts:AssumeRole
4. Calls secretsmanager:ListSecrets → finds payment-related secret names:
   - prod/payment-gateway/stripe-keys
   - prod/payment-gateway/braintree-credentials
   - prod/internal-api/service-accounts
5. Calls secretsmanager:GetSecretValue on each → retrieves:
   - Stripe live-mode secret key, publishable key, webhook secret
   - Braintree merchant ID, public/private keys, tokenization key
   - Internal service API keys, JWT signing secrets, OAuth client secrets
6. Attempts to use payment credentials (Stripe charges, Braintree transactions) → triggers detection
7. Attempts internal API access with service account keys → triggers detection
```

## AWS Resources Deployed

| Resource | Type | Pricing Model |
|----------|------|---------------|
| IAM Role + Policy | AWS::IAM::Role, AWS::IAM::Policy | Free |
| Secrets Manager Secret x3 | AWS::SecretsManager::Secret | $0.40/secret/month |
| Secret Resource Policies x3 | AWS::SecretsManager::ResourcePolicy | Free |

## Monthly Cost Estimation

| Component | Estimate |
|-----------|----------|
| Secrets Manager storage (3 secrets) | ~$1.20 |
| Secrets Manager API calls (minimal, attacker-triggered) | ~$0.00 |
| IAM resources | $0.00 |
| **Total** | **~$1.20/month** |

Cost is driven entirely by Secrets Manager's per-secret pricing ($0.40/secret/month).
API call costs are negligible ($0.05 per 10,000 calls).


