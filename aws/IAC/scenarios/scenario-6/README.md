# Scenario 6 — Lambda Lure: Environment Variable Secrets + Execution Role Pivot

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`lambda-ops-readonly-role` — assumable by any principal in the account. The
role grants read-only access to Lambda function metadata and configuration.

The attacker lists Lambda functions and finds `prod-data-sync-processor`.
Reading its configuration reveals environment variables containing what appear
to be live production credentials:

- RDS database connection (host, user, password)
- Stripe live API key
- Slack webhook URL
- AES encryption key

Investigating the Lambda execution role (`prod-data-sync-exec-role`) reveals
it has read access to three additional lure stores:

- S3 bucket with pipeline configs and partner API keys
- Secrets Manager secret with third-party API credentials
- SSM parameter with internal service endpoints and auth tokens

All values look legitimate and usable. The realistic naming, structure, and
credential formats are designed to lure the attacker into attempting to use
them — triggering detection alerts.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: lambda-ops-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains lambda:ListFunctions, lambda:GetFunction,
  │                    lambda:GetFunctionConfiguration, lambda:ListTags,
  │                    lambda:InvokeFunction, lambda:UpdateFunctionCode
  │                    (scoped to prod-data-sync-processor ONLY)
  │
  ├─► Lists Lambda functions → finds prod-data-sync-processor
  │
  ├─► Reads function configuration → extracts environment variables:
  │     ├─► DB_HOST, DB_USER, DB_PASSWORD (RDS connection)
  │     ├─► STRIPE_API_KEY (payment processing)
  │     ├─► SLACK_WEBHOOK_URL (internal notifications)
  │     ├─► ENCRYPTION_KEY (AES data-at-rest key)
  │     └─► S3_ARTIFACT_BUCKET (hints at more data)
  │
  ├─► Investigates Lambda execution role: prod-data-sync-exec-role
  │     └─► Has read access to:
  │           ├─► S3: prod-data-sync-artifacts-<account-id>
  │           ├─► Secrets Manager: prod/data-sync/api-credentials
  │           └─► SSM: /prod/data-sync/config
  │
  ├─► [OPTIONAL] Steals execution role credentials:
  │     ├─► UpdateFunctionCode → injects credential exfiltration payload
  │     ├─► InvokeFunction → executes payload, returns ASIA session token
  │     ├─► Uses stolen creds to access S3, Secrets Manager, SSM
  │     └─► Restores original code (cleanup)
  │
  └─► Attacker attempts to use credentials ─► triggers alerts
```

## Attack Paths

### Path A: Discovery Only (read env vars)
Low-effort, low-signal. Attacker reads Lambda config and extracts credentials from environment variables. Generates `AssumeRole` + `GetFunctionConfiguration` signals.

### Path B: Execution Role Theft (code injection)
High-effort, high-signal. Attacker updates function code with a credential-exfiltration payload, invokes it, and receives the execution role's temporary ASIA credentials. Then uses those to access S3, Secrets Manager, and SSM directly. Generates `UpdateFunctionCode` + `InvokeFunction` signals — extremely high confidence alerts.

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `lambda-ops-readonly-role` |
| Execution Role | IAM Role | `prod-data-sync-exec-role` |
| Lambda Function | Lambda | `prod-data-sync-processor` |
| Artifacts Bucket | S3 | `prod-data-sync-artifacts-<account-id>` |
| API Credentials | Secrets Manager | `prod/data-sync/api-credentials` |
| Pipeline Config | SSM Parameter | `/prod/data-sync/config` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — Lambda + 2 IAM roles + S3 + Secrets Manager + SSM |
| `deploy.sh` | One-command deploy script — creates the stack and seeds all data stores |
| `abuse.sh` | Attack simulation — reads config, optionally steals exec role creds via code injection |
| `fake-data/pipeline-config.json` | Fake ETL pipeline configuration with internal endpoints |
| `fake-data/partner-api-keys.json` | Fake Salesforce, HubSpot, and Segment API credentials |
| `fake-data/api-credentials.json` | Fake third-party API credentials (Secrets Manager) |
| `fake-data/data-sync-config.json` | Fake internal service config with auth tokens (SSM) |

## Security Best Practices Applied

- S3 bucket: PublicAccessBlock (all four settings true), AES256 encryption, versioning enabled, TLS-only bucket policy
- Secrets Manager: resource policy scoped to account root principal only
- IAM discovery role: trust policy scoped to account root principal (not public)
- IAM execution role: trust policy scoped to `lambda.amazonaws.com` service principal only (not assumable by humans)
- Discovery role: `ListFunctions` on `*` (AWS requirement), all other Lambda actions scoped to specific function ARN
- Discovery role: `InvokeFunction` + `UpdateFunctionCode` scoped to specific function ARN only
- Execution role permissions scoped to specific resource ARNs (least privilege)
- Lambda function: no public URL, no function URL, no API Gateway trigger
- Lambda CloudWatch Logs permission scoped to specific log group ARN

## Detection Signals

| Signal | CloudTrail Event | Confidence |
|--------|-----------------|------------|
| Role assumption | AssumeRole on `lambda-ops-readonly-role` | High |
| Config read | GetFunctionConfiguration on `prod-data-sync-processor` | High |
| Code injection | UpdateFunctionCode on `prod-data-sync-processor` | **Critical** |
| Function invoke | Invoke on `prod-data-sync-processor` | **Critical** |
| S3 read (via stolen creds) | GetObject on `prod-data-sync-artifacts-*` | High |
| Secret read (via stolen creds) | GetSecretValue on `prod/data-sync/api-credentials` | High |
| SSM read (via stolen creds) | GetParameter on `/prod/data-sync/config` | High |

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
  --stack-name deception-scenario-6 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset

aws s3 cp fake-data/pipeline-config.json \
  s3://prod-data-sync-artifacts-${ACCOUNT_ID}/config/pipeline-config.json

aws s3 cp fake-data/partner-api-keys.json \
  s3://prod-data-sync-artifacts-${ACCOUNT_ID}/credentials/partner-api-keys.json

aws secretsmanager put-secret-value \
  --secret-id prod/data-sync/api-credentials \
  --secret-string file://fake-data/api-credentials.json

aws ssm put-parameter \
  --name /prod/data-sync/config \
  --value file://fake-data/data-sync-config.json \
  --type String \
  --overwrite
```

## Teardown

```bash
# Empty the S3 bucket first (required before stack deletion)
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
aws s3 rm s3://prod-data-sync-artifacts-${ACCOUNT_ID} --recursive

aws cloudformation delete-stack --stack-name deception-scenario-6 --region us-west-2
```
