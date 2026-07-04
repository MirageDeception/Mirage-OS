# Scenario 18 — Resource Tags Breadcrumb Trail

## Prompt

Create a deception scenario called `scenario-18` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: resource-inventory-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Uses tag:GetResources or service-specific describe/list calls
  │
  ├─► Finds resources with breadcrumb tags:
  │     ├─► IAM Role tag: ConfigBackup=s3://prod-config-backup-vault/iam-export.json
  │     ├─► Lambda tag: SecretsRef=arn:aws:secretsmanager:...:prod/master-api-keys
  │     ├─► S3 Bucket tag: EncryptionKeyRef=alias/prod-master-encryption
  │     ├─► SSM Parameter tag: RelatedRole=arn:aws:iam::...:role/prod-data-admin-role
  │     └─► DynamoDB tag: BackupBucket=s3://prod-dynamodb-backups/customer-data/
  │
  ├─► Follows breadcrumbs to other resources (which may or may not exist)
  │
  └─► Each lookup generates CloudTrail events → triggers detection
```

### Lure Resources

- **IAM Role (Discovery)**: Named `resource-inventory-readonly-role`
  - `tag:GetResources`, `tag:GetTagKeys`, `tag:GetTagValues`
  - `resourcegroupstaggingapi:GetResources`
  - `iam:ListRoleTags`, `lambda:ListTags`, `s3:GetBucketTagging`
  - Trust: account root principal

- **Breadcrumb resources** (minimal, just need to exist with tags):
  - IAM Role: `prod-backup-automation-role` with tag `ConfigBackup=s3://prod-config-backup-vault/iam-export.json`
  - SSM Parameter: `/prod/inventory/service-registry` with tag `RelatedRole=arn:aws:iam::<account-id>:role/prod-data-admin-role`
  - (The S3 buckets and secrets referenced in tags do NOT need to exist — they're breadcrumbs)

### Additional Requirements

- [ ] Cost: $0.00/month (IAM + SSM Standard = free)
- [ ] Tags reference resources that may or may not exist — the point is the breadcrumb trail
- [ ] Include `deploy.sh`, `README.md`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-18/
├── template.yaml
├── deploy.sh
└── README.md
```
