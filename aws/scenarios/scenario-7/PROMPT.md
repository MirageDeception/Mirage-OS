# Scenario 7 — Lambda Role Chaining: Execution Role → Assumable Pivot Role → Multi-Service Lures

## Prompt

Create a deception scenario called `scenario-7` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content. All credentials and data must look legitimate and usable to
maximize attacker engagement.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: compliance-audit-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains lambda:ListFunctions, lambda:GetFunction,
  │                    lambda:GetFunctionConfiguration
  │
  ├─► Lists Lambda functions → finds prod-compliance-report-generator
  │
  ├─► Reads function configuration → extracts environment variables:
  │     ├─► REPORT_DB_HOST, REPORT_DB_USER, REPORT_DB_PASSWORD
  │     ├─► PIVOT_ROLE_ARN (hints at a more privileged role)
  │     └─► REPORT_BUCKET, AUDIT_LOG_PARAM
  │
  ├─► Investigates Lambda execution role: prod-compliance-exec-role
  │     └─► Has sts:AssumeRole on prod-compliance-data-access-role
  │
  ├─► Assumes pivot role: prod-compliance-data-access-role
  │     (trust policy: root principal — also directly assumable)
  │     └─► Has read access to three separate lure stores:
  │
  │         ┌─────────────────────────────────────────────────────┐
  │         │  S3: compliance-audit-reports-<account-id>          │
  │         │    ├─► reports/pci-dss-2024-q4.json (PCI audit)    │
  │         │    ├─► reports/sox-controls-2024.json (SOX data)   │
  │         │    └─► exports/customer-data-export.csv (PII)      │
  │         │                                                     │
  │         │  Secrets Manager: prod/compliance/encryption-keys   │
  │         │    └─► KMS key material, data encryption keys       │
  │         │                                                     │
  │         │  SSM: /prod/compliance/database-credentials         │
  │         │    └─► Compliance DB connection string              │
  │         │                                                     │
  │         │  SSM: /prod/compliance/third-party-integrations     │
  │         │    └─► SOC2 vendor API keys, audit platform creds   │
  │         └─────────────────────────────────────────────────────┘
  │
  └─► Attacker attempts to use credentials ─► triggers alerts
```

### Lure Resources

- **IAM Role 1 (Discovery)**: Named `compliance-audit-readonly-role`
  - `lambda:ListFunctions`
  - `lambda:GetFunction`
  - `lambda:GetFunctionConfiguration`
  - `lambda:ListTags`
  - `sts:AssumeRole` in trust policy by anyone in this account (root principal)

- **Lambda Function**: Named `prod-compliance-report-generator`
  - Runtime: python3.12
  - Handler: index.handler
  - Minimal inline code (looks like a compliance report generator)
  - Environment variables:
    - `REPORT_DB_HOST`: `prod-compliance-db.d7bktj3f8uap.us-west-2.rds.amazonaws.com`
    - `REPORT_DB_PORT`: `5432`
    - `REPORT_DB_NAME`: `compliance_production`
    - `REPORT_DB_USER`: `compliance_report_svc`
    - `REPORT_DB_PASSWORD`: `C0mpl1@nc3#Rpt!2024sVx`
    - `PIVOT_ROLE_ARN`: `arn:aws:iam::<account-id>:role/prod-compliance-data-access-role`
    - `REPORT_BUCKET`: `compliance-audit-reports-<account-id>`
    - `AUDIT_LOG_PARAM`: `/prod/compliance/database-credentials`
  - Tags: `Environment=production`, `Project=compliance-platform`, `ManagedBy=terraform`

- **IAM Role 2 (Lambda Execution)**: Named `prod-compliance-exec-role`
  - Trust policy: `lambda.amazonaws.com` service principal
  - Permissions:
    - `sts:AssumeRole` — scoped to `prod-compliance-data-access-role` ARN only
    - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

- **IAM Role 3 (Pivot / Data Access)**: Named `prod-compliance-data-access-role`
  - Trust policy: account root principal (any identity can assume it directly too)
  - This is the key role-chaining target
  - Permissions:
    - `s3:ListBucket`, `s3:GetObject` — scoped to `compliance-audit-reports-<account-id>`
    - `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` — scoped to `prod/compliance/encryption-keys`
    - `ssm:GetParameter` — scoped to `/prod/compliance/database-credentials` and `/prod/compliance/third-party-integrations`
    - `ssm:DescribeParameters`

- **S3 Bucket**: Named `compliance-audit-reports-<account-id>`
  - Contains fake compliance reports and data exports:
    - `reports/pci-dss-2024-q4.json` — fake PCI DSS audit report with card data references
    - `reports/sox-controls-2024.json` — fake SOX controls assessment
    - `exports/customer-data-export.csv` — fake PII export (names, emails, SSNs)
  - Bucket policy allows read from account root principal
  - Full security best practices

- **Secrets Manager Secret**: Named `prod/compliance/encryption-keys`
  - Contains fake data encryption keys and KMS key references
  - Resource policy allows read from account root principal

- **SSM Parameter 1**: Named `/prod/compliance/database-credentials`
  - Contains fake compliance database connection string

- **SSM Parameter 2**: Named `/prod/compliance/third-party-integrations`
  - Contains fake SOC2 vendor API keys and audit platform credentials

### Fake Data to Seed

- `fake-data/pci-dss-2024-q4.json`:
  ```json
  {
    "report_type": "PCI-DSS Compliance Assessment",
    "period": "2024-Q4",
    "status": "passed_with_observations",
    "assessor": "SecureAudit Partners LLC",
    "cardholder_data_environment": {
      "network_segments": ["10.0.50.0/24", "10.0.51.0/24"],
      "encryption_standard": "AES-256-GCM",
      "key_rotation_days": 90,
      "tokenization_provider": "acme-token-vault.prod.internal.corp",
      "pan_storage_locations": [
        "prod-payments-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com:payments_prod.card_data",
        "s3://prod-payment-archives-encrypted/card-transactions/"
      ]
    },
    "observations": [
      "Requirement 8.3.1: MFA not enforced for all admin console access",
      "Requirement 10.6.1: Log review automation incomplete for 2 systems"
    ]
  }
  ```

- `fake-data/sox-controls-2024.json`:
  ```json
  {
    "report_type": "SOX IT General Controls Assessment",
    "fiscal_year": "2024",
    "status": "effective",
    "controls": [
      {
        "control_id": "ITGC-AC-001",
        "description": "Access provisioning and deprovisioning",
        "owner": "iam-admin@acme-corp.com",
        "systems": ["AWS IAM", "Okta", "Active Directory"],
        "admin_credentials_vault": "https://vault.prod.internal.corp/v1/secret/data/sox-admin"
      },
      {
        "control_id": "ITGC-CM-003",
        "description": "Change management for production databases",
        "owner": "dba-team@acme-corp.com",
        "approval_system": "https://jira.prod.internal.corp/projects/DBCM",
        "db_admin_jumpbox": "10.0.2.50"
      }
    ]
  }
  ```

- `fake-data/customer-data-export.csv`:
  ```csv
  customer_id,full_name,email,phone,ssn_last4,account_status,lifetime_value
  CUST-00001,[name],[email],[phone],4821,active,12450.00
  CUST-00002,[name],[email],[phone],7293,active,8920.50
  CUST-00003,[name],[email],[phone],1547,suspended,3200.00
  CUST-00004,[name],[email],[phone],6038,active,45100.75
  CUST-00005,[name],[email],[phone],9412,active,22340.00
  ```

- `fake-data/encryption-keys.json` (for Secrets Manager):
  ```json
  {
    "data_encryption_key": "aes256:e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6",
    "kms_key_arn": "arn:aws:kms:us-west-2:<account-id>:key/mrk-a1b2c3d4e5f6a7b8c9d0e1f2",
    "backup_encryption_key": "aes256:1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
    "token_vault_master_key": "tv_mk_prod_xK9mP2vL5nQ8wR1tY4uJ7hG3fD6sA0",
    "certificate_private_key_passphrase": "c3rt_pk_p@ss_pr0d_2024"
  }
  ```

- `fake-data/database-credentials.json` (for SSM parameter):
  ```json
  {
    "host": "prod-compliance-db.d7bktj3f8uap.us-west-2.rds.amazonaws.com",
    "port": 5432,
    "database": "compliance_production",
    "username": "compliance_admin",
    "password": "C0mpl1@nc3Adm1n#Pr0d!2024",
    "ssl_mode": "verify-full",
    "connection_string": "postgresql://compliance_admin:C0mpl1@nc3Adm1n#Pr0d!2024@prod-compliance-db.d7bktj3f8uap.us-west-2.rds.amazonaws.com:5432/compliance_production?sslmode=verify-full"
  }
  ```

- `fake-data/third-party-integrations.json` (for SSM parameter):
  ```json
  {
    "soc2_audit_platform": {
      "provider": "Vanta",
      "api_key": "vnt_prod_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
      "org_id": "org_acme_prod_7x9k2m",
      "webhook_secret": "whsec_vnt_7kL2mN9pQ1rS3uV5wX8yZ0"
    },
    "vulnerability_scanner": {
      "provider": "Qualys",
      "api_url": "https://qualysapi.qualys.com",
      "username": "acme_api_prod",
      "password": "Qu@lys_@p1_pr0d_2024xM7n"
    },
    "siem_integration": {
      "provider": "Splunk",
      "hec_endpoint": "https://splunk-hec.prod.internal.corp:8088",
      "hec_token": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    }
  }
  ```

### Resource Naming Style

- Lambda: `prod-compliance-report-generator`
- Roles: `compliance-audit-readonly-role`, `prod-compliance-exec-role`, `prod-compliance-data-access-role`
- S3: `compliance-audit-reports-<account-id>`
- Secret: `prod/compliance/encryption-keys`
- SSM: `/prod/compliance/database-credentials`, `/prod/compliance/third-party-integrations`
- Tags: `Environment=production`, `Project=compliance-platform`, `ManagedBy=terraform`, `CostCenter=CC-8210`

### Role Chaining Path

```
compliance-audit-readonly-role (attacker assumes)
  │
  ├─► Reads Lambda config → discovers PIVOT_ROLE_ARN env var
  │
  ├─► prod-compliance-exec-role (Lambda execution role)
  │     └─► Can sts:AssumeRole → prod-compliance-data-access-role
  │
  └─► prod-compliance-data-access-role (pivot target)
        ├─► Also assumable directly by root (attacker can skip the chain)
        ├─► S3 read: compliance-audit-reports-<account-id>
        ├─► Secrets Manager read: prod/compliance/encryption-keys
        └─► SSM read: /prod/compliance/database-credentials
                      /prod/compliance/third-party-integrations
```

### Additional Requirements

- [ ] All resources must follow security best practices (encryption, no public access, least privilege)
- [ ] Lambda function should have minimal inline code that looks like a real compliance report generator
- [ ] Lambda execution role ONLY has sts:AssumeRole to the pivot role (plus CloudWatch logs)
- [ ] Pivot role is independently assumable by root — attacker can discover it via Lambda or find it directly
- [ ] Each lure store (S3, Secrets Manager, SSM) has different themed data (compliance/audit domain)
- [ ] Include a `deploy.sh` bash script that deploys the stack and seeds all data — with comments
- [ ] Include a `README.md` explaining the role chaining path, resource listing, and deployment steps
- [ ] Default region: `us-west-2`
- [ ] Place everything under `scenarios/scenario-7/`

### Output Structure

```
scenarios/scenario-7/
├── template.yaml
├── deploy.sh
├── fake-data/
│   ├── pci-dss-2024-q4.json
│   ├── sox-controls-2024.json
│   ├── customer-data-export.csv
│   ├── encryption-keys.json
│   ├── database-credentials.json
│   └── third-party-integrations.json
└── README.md
```
