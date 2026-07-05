# Scenario 16 — KMS Key Lure: Customer Data Encryption Key

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`kms-audit-readonly-role` — assumable by any principal in the account. The
role grants read-only access to KMS key metadata and policies.

The attacker lists KMS aliases and finds `alias/prod-customer-data-encryption`.
Describing the key reveals it is a customer-managed symmetric key used for
PII encryption in the payment and user data platform. The key policy references
service principals for Lambda, RDS, and S3 — revealing internal architecture.

Attempting to decrypt or generate data keys is explicitly denied by both the
IAM policy and the KMS key policy. The denied attempt generates a CloudTrail
event that serves as a high-confidence detection signal.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: kms-audit-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains kms:ListAliases, kms:ListKeys,
  │                    kms:DescribeKey, kms:ListGrants,
  │                    kms:ListKeyPolicies, kms:GetKeyPolicy
  │
  ├─► Lists aliases → finds alias/prod-customer-data-encryption
  │
  ├─► Describes key → sees metadata, creation date, rotation status
  │
  ├─► Lists grants → sees grants referencing Lambda, RDS, S3
  │
  ├─► Gets key policy → reads full policy with service principals
  │
  ├─► Attempts kms:Decrypt → DENIED (detection signal)
  │
  └─► Key policy and grants reveal service principals and resource ARNs
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `kms-audit-readonly-role` |
| Encryption Key | KMS Key | `alias/prod-customer-data-encryption` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — KMS key + alias + IAM role with deny policy |
| `deploy.sh` | One-command deploy script — creates the stack |
| `abuse.sh` | Simulates the attacker abuse chain step by step |

## Security Best Practices Applied

- IAM discovery role: trust policy scoped to account root principal (not public)
- Discovery role permissions scoped to specific key ARN (except ListAliases/ListKeys)
- Decrypt/Encrypt explicitly denied in both IAM policy and KMS key policy (defense in depth)
- KMS key rotation enabled
- Key policy uses `kms:ViaService` condition for service principal access
- No cross-account access

## Cost

~$1.00/month for the single KMS customer-managed key.

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

## Teardown

```bash
# Schedule key deletion (7-day minimum waiting period)
aws cloudformation delete-stack --stack-name deception-scenario-16 --region us-west-2
```
