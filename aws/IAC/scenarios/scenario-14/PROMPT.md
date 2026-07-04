# Scenario 16 — KMS Key Lure: Customer Data Encryption Key

## Prompt

Create a deception scenario called `scenario-16` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: kms-audit-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► kms:ListAliases → finds alias/prod-customer-data-encryption
  │
  ├─► kms:DescribeKey → sees key metadata, creation date, key manager
  │
  ├─► kms:ListGrants → sees grants referencing Lambda, RDS, S3
  │
  ├─► kms:ListKeyPolicies / kms:GetKeyPolicy → reads key policy
  │
  ├─► Attempts kms:Decrypt or kms:GenerateDataKey → DENIED
  │   (but the attempt is logged as a detection signal)
  │
  └─► Key policy and grants reveal service principals and resource ARNs
      that become breadcrumbs to other lures
```

### Lure Resources

- **IAM Role**: Named `kms-audit-readonly-role`
  - `kms:ListAliases`, `kms:ListKeys`
  - `kms:DescribeKey`, `kms:ListGrants`, `kms:ListKeyPolicies`, `kms:GetKeyPolicy` — scoped to lure key
  - Trust: account root principal
  - Explicitly DENIED: `kms:Decrypt`, `kms:Encrypt`, `kms:GenerateDataKey`

- **KMS Key**: Customer-managed symmetric key
  - Alias: `alias/prod-customer-data-encryption`
  - Description: `Customer PII encryption key for production payment and user data`
  - Key policy allows describe/list from account, deny decrypt from the lure role
  - Tags: `Environment=production`, `Project=customer-platform`, `DataClassification=PII`

### Additional Requirements

- [ ] Cost: ~$1.00/month (single KMS key)
- [ ] Lure role can describe but NOT use the key (deny decrypt explicitly)
- [ ] Key policy should reference realistic service principals (lambda, rds, s3)
- [ ] Include `deploy.sh`, `README.md`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-16/
├── template.yaml
├── deploy.sh
└── README.md
```
