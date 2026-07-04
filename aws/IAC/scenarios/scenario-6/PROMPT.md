# Scenario 6 — Lambda Lure: Environment Variable Secrets + Execution Role Pivot

## Prompt

Create a deception scenario called `scenario-6` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content. All credentials and data must look legitimate and usable to
maximize attacker engagement.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: lambda-ops-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains lambda:ListFunctions, lambda:GetFunction,
  │                    lambda:GetFunctionConfiguration
  │
  ├─► Lists Lambda functions → finds prod-data-sync-processor
  │
  ├─► Reads function configuration → extracts environment variables:
  │     ├─► DB_HOST, DB_USER, DB_PASSWORD (RDS connection)
  │     ├─► STRIPE_API_KEY (payment processing)
  │     ├─► SLACK_WEBHOOK_URL (internal notifications)
  │     ├─► ENCRYPTION_KEY (AES data-at-rest key)
  │     └─► AWS_LAMBDA_EXEC_ROLE_ARN (hints at execution role)
  │
  ├─► Investigates Lambda execution role: prod-data-sync-exec-role
  │     └─► Has read access to:
  │           ├─► S3 bucket: prod-data-sync-artifacts-<account-id>
  │           ├─► Secrets Manager: prod/data-sync/api-credentials
  │           └─► SSM Parameter: /prod/data-sync/config
  │
  ├─► Invokes the function (if invoke permission exists) or
  │   reads the linked resources directly via execution role
  │
  └─► Attacker attempts to use credentials ─► triggers alerts
```

### Lure Resources

- **IAM Role 1 (Discovery)**: Named `lambda-ops-readonly-role`
  - `lambda:ListFunctions`
  - `lambda:GetFunction`
  - `lambda:GetFunctionConfiguration`
  - `lambda:ListTags`
  - `sts:AssumeRole` in trust policy by anyone in this account (root principal)

- **Lambda Function**: Named `prod-data-sync-processor`
  - Runtime: python3.12
  - Handler: index.handler
  - Minimal inline code (just returns a status message — looks like a data sync job)
  - Environment variables containing secrets:
    - `DB_HOST`: `prod-analytics-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com`
    - `DB_PORT`: `5432`
    - `DB_NAME`: `analytics_production`
    - `DB_USER`: `analytics_etl_svc`
    - `DB_PASSWORD`: `An@lyt1cs#ETL!2024pR0d`
    - `STRIPE_API_KEY`: `sk_live_51QxHr8eF59JrNzkYGctjU3af2rq9ef`
    - `SLACK_WEBHOOK_URL`: `https://hooks.slack.com/services/T0PROD01/B0PROD02/xYzAbCdEfGhIjKlMnOpQrStU`
    - `ENCRYPTION_KEY`: `aes256:9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d`
    - `S3_ARTIFACT_BUCKET`: `prod-data-sync-artifacts-<account-id>`
  - Tags: `Environment=production`, `Project=data-platform`, `ManagedBy=terraform`

- **IAM Role 2 (Lambda Execution)**: Named `prod-data-sync-exec-role`
  - Trust policy: `lambda.amazonaws.com` service principal
  - Permissions:
    - `s3:GetObject`, `s3:ListBucket` — scoped to `prod-data-sync-artifacts-<account-id>`
    - `secretsmanager:GetSecretValue` — scoped to `prod/data-sync/api-credentials`
    - `ssm:GetParameter` — scoped to `/prod/data-sync/config`
    - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` — for CloudWatch (looks real)

- **S3 Bucket**: Named `prod-data-sync-artifacts-<account-id>`
  - Contains fake data pipeline artifacts:
    - `config/pipeline-config.json` — pipeline configuration with internal endpoints
    - `credentials/partner-api-keys.json` — fake partner API credentials
  - Bucket policy allows read from account root principal
  - Full security best practices (encryption, versioning, public access block, TLS-only)

- **Secrets Manager Secret**: Named `prod/data-sync/api-credentials`
  - Contains fake third-party API credentials (Salesforce, HubSpot, Segment)
  - Resource policy allows read from account root principal

- **SSM Parameter**: Named `/prod/data-sync/config`
  - Contains fake pipeline configuration with internal service URLs and auth tokens

### Fake Data to Seed

- `fake-data/pipeline-config.json`:
  ```json
  {
    "pipeline_id": "ds-prod-001",
    "source": {
      "type": "postgresql",
      "host": "prod-analytics-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com",
      "port": 5432,
      "database": "analytics_production",
      "schema": "public"
    },
    "destinations": [
      {
        "type": "s3",
        "bucket": "prod-data-lake-raw",
        "prefix": "analytics/daily/"
      },
      {
        "type": "redshift",
        "cluster": "prod-analytics-cluster.abc123.us-west-2.redshift.amazonaws.com",
        "database": "analytics_warehouse",
        "schema": "etl_staging"
      }
    ],
    "schedule": "cron(0 2 * * ? *)",
    "notification_channel": "https://hooks.slack.com/services/T0PROD01/B0PROD02/xYzAbCdEfGhIjKlMnOpQrStU"
  }
  ```

- `fake-data/partner-api-keys.json`:
  ```json
  {
    "salesforce": {
      "client_id": "3MVG9d8..zR5.Bh7kLmNoPqRsTuVwXyZ",
      "client_secret": "A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6",
      "refresh_token": "5Aep861..kLmNoPqRsTuVwXyZaBcDeFgHiJk",
      "instance_url": "https://acme-corp.my.salesforce.com"
    },
    "hubspot": {
      "api_key": "pat-na1-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "portal_id": "12345678"
    },
    "segment": {
      "write_key": "wk_prod_a1B2c3D4e5F6g7H8i9J0kLmN"
    }
  }
  ```

- `fake-data/data-sync-config.json` (for SSM parameter):
  ```json
  {
    "auth_service": "https://auth.prod.internal.corp/oauth/token",
    "auth_client_id": "data-sync-svc-prod",
    "auth_client_secret": "oAuth_cl13nt_s3cr3t_pr0d_9xK2mV",
    "data_lake_endpoint": "https://datalake.prod.internal.corp/api/v1",
    "data_lake_api_key": "dlk_prod_7fA9bC1dE3gH5iJ7kL9mN",
    "retry_max": 3,
    "timeout_seconds": 300
  }
  ```

- `fake-data/api-credentials.json` (for Secrets Manager):
  ```json
  {
    "salesforce_oauth": {
      "client_id": "3MVG9d8..zR5.Bh7kLmNoPqRsTuVwXyZ",
      "client_secret": "A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6",
      "refresh_token": "5Aep861..kLmNoPqRsTuVwXyZaBcDeFgHiJk"
    },
    "hubspot_api": {
      "api_key": "pat-na1-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    },
    "internal_data_api": {
      "endpoint": "https://api.prod.internal.corp/v2/data-ingest",
      "api_key": "dapi_prod_xK9mP2vL5nQ8wR1tY4uJ7hG3"
    }
  }
  ```

### Resource Naming Style

- Lambda: `prod-data-sync-processor`
- Roles: `lambda-ops-readonly-role`, `prod-data-sync-exec-role`
- S3: `prod-data-sync-artifacts-<account-id>`
- Secret: `prod/data-sync/api-credentials`
- SSM: `/prod/data-sync/config`
- Tags: `Environment=production`, `Project=data-platform`, `ManagedBy=terraform`, `CostCenter=CC-6140`

### Additional Requirements

- [ ] All resources must follow security best practices (encryption, no public access, least privilege)
- [ ] Lambda function should have minimal inline code that looks like a real data sync handler
- [ ] Lambda execution role scoped to specific resource ARNs only
- [ ] Include a `deploy.sh` bash script that deploys the stack and seeds all data — with comments
- [ ] Include a `README.md` explaining the deception chain, resource listing, and deployment steps
- [ ] Default region: `us-west-2`
- [ ] Place everything under `scenarios/scenario-6/`

### Output Structure

```
scenarios/scenario-6/
├── template.yaml
├── deploy.sh
├── fake-data/
│   ├── pipeline-config.json
│   ├── partner-api-keys.json
│   ├── data-sync-config.json
│   └── api-credentials.json
└── README.md
```
