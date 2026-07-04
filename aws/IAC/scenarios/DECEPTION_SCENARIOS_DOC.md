# AWS Cloud Deception Scenarios

## Overview

This project deploys internal-only AWS deception infrastructure to detect insider threats and attackers who have already gained access to an AWS account. Each scenario creates a realistic resource chain with enticing names and fake credentials that lure attackers into interacting with honeypot resources — generating high-fidelity CloudTrail detection signals.

All resources follow AWS security best practices to blend in with legitimate infrastructure. Credentials and data look real but are completely fake.

| Property | Value |
|----------|-------|
| Region | us-west-2 |
| Total scenarios | 19 |
| Total monthly cost | ~$3.70 |
| IaC | CloudFormation |
| Access model | Internal account only (root principal) |

---

## Design Principles

- **Internal only** — all lures target insider threats or attackers already in the account
- **No public access** — every resource has public access fully blocked
- **No cross-account** — no external account references or trust policies
- **No IAM users** — only IAM roles used throughout
- **Least privilege** — each role only gets the exact permissions the scenario requires
- **No giveaway labels** — no FAKE/EXPIRED/REVOKED in any data; everything looks legitimate

---

## Detection Strategy

Detection is tuned for **high-confidence, low-noise alerts**. We monitor two categories of CloudTrail events:

**1. AssumeRole on lure roles** — no legitimate user should assume these decoy roles. Any AssumeRole event targeting a lure role name is a true positive.

**2. Resource-specific API calls on exact lure resource ARNs** — calls that require a specific resource identifier (ARN, name, or ID) and target a decoy resource. If someone is calling `DescribeKey` on our decoy KMS key or `GetObject` on our decoy S3 bucket, they found the lure and are actively investigating it.

**Excluded from monitoring (false positive reduction):**

All broad enumeration calls that return every resource of a type without targeting a specific one. These are made routinely by legitimate users, automation, AWS Config, and Security Hub:

`ListBuckets`, `ListSecrets`, `DescribeParameters`, `ListTables`, `ListQueues`, `ListTopics`, `ListFunctions`, `ListRoles`, `ListAliases`, `ListKeys`, `DescribeLogGroups`, `ListStacks`, `ListSAMLProviders`, `ListExports`, `DescribeLogStreams`

**Kept in monitoring (resource-specific):**

`AssumeRole`, `GetObject`, `GetSecretValue`, `GetParameter`, `GetParametersByPath`, `Scan`, `Query`, `GetItem`, `ReceiveMessage`, `BatchGetImage`, `GetDownloadUrlForLayer`, `StartInstances`, `AuthorizeSecurityGroupIngress`, `Decrypt`, `DescribeKey`, `DescribeStacks`, `DescribeTable`, `GetTopicAttributes`, `GetQueueAttributes`, `GetFunctionConfiguration`, `GetSAMLProvider`, `GetLogEvents`, `FilterLogEvents`, `ListSubscriptionsByTopic`, `Publish`

---

## Scenario Inventory

| # | Name | Lure Type | AWS Services | Cost/mo |
|---|------|-----------|-------------|---------|
| 1 | Terraform State Lure | S3 bucket with fake tfstate | IAM, S3 | $0.00 |
| 2 | Payment Credentials | Secrets Manager secrets | IAM, SecretsManager | $1.20 |
| 3 | Infrastructure Vault | SSM Parameter Store | IAM, SSM | $0.05 |
| 4 | SSH Key → EC2 Bastion | S3 key + stopped EC2 | IAM, S3, EC2 | $0.64 |
| 5 | ECR Container Image | Docker image with secrets | IAM, ECR | $0.01 |
| 6 | Lambda Data Sync | Lambda env vars → S3/SM/SSM | IAM, Lambda, S3, SM, SSM | $0.40 |
| 7 | Lambda Role Chaining | Lambda → pivot role → S3/SM/SSM | IAM, Lambda, S3, SM, SSM | $0.40 |
| 8 | Role Chain Loop | 3 roles in circular chain + SSM | IAM, SSM | $0.00 |
| 9 | Customer Profiles | DynamoDB with fake PII | IAM, DynamoDB | $0.00 |
| 10 | Active Sessions | DynamoDB with fake JWTs | IAM, DynamoDB | $0.00 |
| 11 | Payment Events DLQ | SQS FIFO with fake transactions | IAM, SQS | $0.00 |
| 12 | Critical Alerts | SNS topic with endpoints | IAM, SNS | $0.00 |
| 13 | Leaked Logs | CloudWatch Logs with creds in traces | IAM, CloudWatch | $0.00 |
| 14 | Encryption Key | KMS key (describe-only, deny decrypt) | IAM, KMS | $1.00 |
| 15 | Fake SSO | SAML provider with Okta metadata | IAM, SAML | $0.00 |
| 16 | Tag Breadcrumbs | Resource tags referencing other lures | IAM, Tags, SSM | $0.00 |
| 17 | Enriched User PII | Lambda + DynamoDB with enriched profiles | IAM, Lambda, DynamoDB | $0.00 |
| 18 | SSM Chain | 5 SSM params cross-referencing each other | IAM, SSM | $0.00 |
| 19 | Stack Outputs | CloudFormation outputs with secrets | IAM, CloudFormation, SSM | $0.00 |

---

## Scenario 1 — S3 Terraform State Lure

**Role**: `infra-s3-data-readonly-role` · **Folder**: `scenario-1` · **Cost**: $0.00/mo

Attacker assumes a role that grants S3 read access, discovers a bucket named `infra-terraform-state-<account-id>`, and downloads a Terraform state file containing RDS credentials, Stripe API keys, IAM access keys, Redis auth tokens, and SSM connection strings.

```
Attacker → AssumeRole → GetObject (terraform.tfstate)
             → Extracts: RDS creds, Stripe keys, IAM keys, Redis token, DB connection string
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/infra-s3-data-readonly-role` |
| State file download | GetObject | `infra-terraform-state-<acct>/env/production/terraform.tfstate` |

---

## Scenario 2 — Secrets Manager Payment Credentials Lure

**Role**: `payment-secrets-readonly-role` · **Folder**: `scenario-2` · **Cost**: $1.20/mo

Attacker assumes a role and reads three Secrets Manager secrets: Stripe keys, Braintree credentials, and internal service account credentials.

```
Attacker → AssumeRole → GetSecretValue × 3
             → Extracts: Stripe sk_live_, Braintree merchant keys, service account API keys
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/payment-secrets-readonly-role` |
| Stripe secret read | GetSecretValue | `secret:prod/payment-gateway/stripe-keys-*` |
| Braintree secret read | GetSecretValue | `secret:prod/payment-gateway/braintree-credentials-*` |
| Service accounts read | GetSecretValue | `secret:prod/internal-api/service-accounts-*` |

---

## Scenario 3 — SSM Parameter Store Infrastructure Vault

**Role**: `infra-config-readonly-role` · **Folder**: `scenario-3` · **Cost**: $0.05/mo

Attacker reads SSM parameters under `/prod/*` containing database master credentials, GitHub deploy token, Datadog API keys, VPN admin credentials, and an EKS cluster-admin kubeconfig.

```
Attacker → AssumeRole → GetParametersByPath /prod/* or GetParameter × 5
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/infra-config-readonly-role` |
| Bulk parameter read | GetParametersByPath | `parameter/prod` |
| Individual reads (×5) | GetParameter | `parameter/prod/database/master-credentials` etc. |

---

## Scenario 4 — S3 SSH Key → EC2 Bastion with Sensitive Files

**Role**: `devops-s3-deploy-role` · **Folder**: `scenario-4` · **Cost**: $0.64/mo

Attacker downloads an SSH key from S3, modifies a security group, starts a stopped bastion instance, and SSHs in to find sensitive files.

```
Attacker → AssumeRole → GetObject (SSH key) → AuthorizeSecurityGroupIngress ⚠️
         → StartInstances ⚠️ → SSH in → finds .env, db-backup-creds, internal-hosts, AWS creds
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/devops-s3-deploy-role` |
| Key download | GetObject | `devops-deploy-keys-<acct>/keys/prod-bastion.pem` |
| SG modification ⚠️ | AuthorizeSecurityGroupIngress | `security-group/<sg-id>` |
| Instance start ⚠️ | StartInstances | `instance/<instance-id>` |
| SSH connection | VPC Flow Logs | Bastion public IP, port 22 |

**Note**: Instance deploys stopped. Combinable with scenario 5 and future scenarios.

---

## Scenario 5 — ECR Container Image with PII & Credentials

**Role**: `prod-bastion-ecr-role` · **Folder**: `scenario-5` · **Cost**: $0.01/mo

Attacker authenticates to ECR, pulls `prod-payment-service` image containing DB creds, Stripe keys, PII records, and AWS session tokens.

```
Attacker → BatchGetImage (pull prod-payment-service) → inspect layers
         → Finds: .env, secrets.json (PII), AWS credentials
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Image pull | BatchGetImage | `repository/prod-payment-service` |
| Layer download | GetDownloadUrlForLayer | `repository/prod-payment-service` |

**Trust**: `ec2.amazonaws.com` (instance profile). Combinable with scenario 4.

---

## Scenario 6 — Lambda Data Sync with Environment Variable Secrets

**Role**: `lambda-ops-readonly-role` · **Folder**: `scenario-6` · **Cost**: $0.40/mo

Attacker reads Lambda function `prod-data-sync-processor` configuration and extracts DB credentials, Stripe key, Slack webhook, and encryption key from environment variables. Execution role pivots to S3, Secrets Manager, and SSM.

```
Attacker → AssumeRole → GetFunctionConfiguration (env vars)
         → Execution role pivots to: S3, Secrets Manager, SSM
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/lambda-ops-readonly-role` |
| Lambda config read | GetFunctionConfiguration | `function:prod-data-sync-processor` |
| S3 artifact read | GetObject | `prod-data-sync-artifacts-<acct>/*` |
| Secret read | GetSecretValue | `secret:prod/data-sync/api-credentials-*` |
| SSM read | GetParameter | `parameter/prod/data-sync/config` |

---

## Scenario 7 — Lambda Role Chaining to Compliance Lures

**Role**: `compliance-audit-readonly-role` · **Folder**: `scenario-7` · **Cost**: $0.40/mo

Attacker reads Lambda function, discovers `PIVOT_ROLE_ARN` env var, and assumes `prod-compliance-data-access-role` which reads S3 (PCI-DSS reports, SOX controls, PII export), Secrets Manager (encryption keys), and SSM (DB creds, vendor API keys).

```
Attacker → AssumeRole (discovery) → GetFunctionConfiguration → discovers PIVOT_ROLE_ARN
         → AssumeRole (pivot) ⚠️ → S3 + SM + SSM reads
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Discovery role assumption | AssumeRole | `role/compliance-audit-readonly-role` |
| Lambda config read | GetFunctionConfiguration | `function:prod-compliance-report-generator` |
| Pivot role assumption ⚠️ | AssumeRole | `role/prod-compliance-data-access-role` |
| S3 report reads | GetObject | `compliance-audit-reports-<acct>/*` |
| Secret read | GetSecretValue | `secret:prod/compliance/encryption-keys-*` |
| SSM reads | GetParameter | `parameter/prod/compliance/*` |

---

## Scenario 8 — IAM Role Chain Loop

**Roles**: `prod-microservice-auth-role` → `data-role` → `admin-role` → loop · **Folder**: `scenario-9` · **Cost**: $0.00/mo

Three roles that assume each other in a circle. Each role has an SSM parameter with themed credentials.

```
auth-role ──► data-role ──► admin-role ──► auth-role (loop)
   │              │              │
   ▼              ▼              ▼
/prod/auth/   /prod/data/   /prod/admin/
oidc-config   lake-creds    console-creds
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumptions (×3+) | AssumeRole | `role/prod-microservice-auth-role`, `-data-role`, `-admin-role` |
| SSM reads (×3) | GetParameter | `parameter/prod/auth/*`, `/prod/data/*`, `/prod/admin/*` |

---

## Scenario 9 — DynamoDB Customer Profiles

**Role**: `customer-data-readonly-role` · **Folder**: `scenario-11` · **Cost**: $0.00/mo

Attacker scans a DynamoDB table `prod-customer-profiles` seeded with 10-15 fake PII records.

```
Attacker → AssumeRole → DescribeTable → Scan/Query (PII records)
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/customer-data-readonly-role` |
| Table describe | DescribeTable | `table/prod-customer-profiles` |
| Data scan | Scan | `table/prod-customer-profiles` |
| Data query | Query | `table/prod-customer-profiles` |

---

## Scenario 10 — DynamoDB Active Sessions

**Role**: `session-store-readonly-role` · **Folder**: `scenario-12` · **Cost**: $0.00/mo

Attacker scans a DynamoDB table `prod-active-sessions` with fake JWT tokens, session IDs, and refresh tokens.

```
Attacker → AssumeRole → DescribeTable → Scan (session records with JWTs)
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/session-store-readonly-role` |
| Table describe | DescribeTable | `table/prod-active-sessions` |
| Session scan | Scan | `table/prod-active-sessions` |

---

## Scenario 11 — SQS Payment Events Dead Letter Queue

**Role**: `payment-queue-readonly-role` · **Folder**: `scenario-13` · **Cost**: $0.00/mo

Attacker reads messages from SQS DLQ `prod-payment-events-dlq.fifo` containing fake payment events with card tokens and amounts.

```
Attacker → AssumeRole → GetQueueAttributes → ReceiveMessage (DLQ)
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/payment-queue-readonly-role` |
| Queue attributes | GetQueueAttributes | `prod-payment-events-dlq.fifo` |
| Message read | ReceiveMessage | `prod-payment-events-dlq.fifo` |

---

## Scenario 12 — SNS Critical Alerts Topic

**Role**: `alerts-readonly-role` · **Folder**: `scenario-14` · **Cost**: $0.00/mo

Attacker discovers SNS topic `prod-alerts-critical` with subscriptions pointing to fake internal webhook URLs and email addresses.

```
Attacker → AssumeRole → GetTopicAttributes → ListSubscriptionsByTopic
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/alerts-readonly-role` |
| Topic attributes | GetTopicAttributes | `prod-alerts-critical` |
| Subscription enumeration | ListSubscriptionsByTopic | `prod-alerts-critical` |
| Publish attempt | Publish | `prod-alerts-critical` |

---

## Scenario 13 — CloudWatch Logs with Leaked Credentials

**Role**: `log-analysis-readonly-role` · **Folder**: `scenario-15` · **Cost**: $0.00/mo

Attacker reads CloudWatch log group `/prod/payment-service/application` containing seeded log entries with accidentally-logged credentials.

```
Attacker → AssumeRole → GetLogEvents / FilterLogEvents
             → Finds: DB connection strings, API keys, passwords in log entries
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/log-analysis-readonly-role` |
| Log reads | GetLogEvents | `log-group:/prod/payment-service/application` |
| Keyword search | FilterLogEvents | `log-group:/prod/payment-service/application` |

---

## Scenario 14 — KMS Customer Data Encryption Key

**Role**: `kms-audit-readonly-role` · **Folder**: `scenario-16` · **Cost**: $1.00/mo

Attacker discovers KMS key `alias/prod-customer-data-encryption`, reads metadata and grants, but decrypt is explicitly denied.

```
Attacker → AssumeRole → DescribeKey → Decrypt → DENIED ⚠️
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/kms-audit-readonly-role` |
| Key metadata | DescribeKey | `key/<key-id>` |
| Decrypt denied ⚠️ | Decrypt (failure) | `key/<key-id>` |

---

## Scenario 15 — SAML Provider (Fake Okta SSO)

**Role**: `sso-audit-readonly-role` · **Folder**: `scenario-17` · **Cost**: $0.00/mo

Attacker discovers SAML provider `ProdOktaSSO` with metadata XML, and SAML-trusted roles that can't be assumed without a valid SAML assertion.

```
Attacker → AssumeRole → GetSAMLProvider (metadata XML)
         → AssumeRoleWithSAML attempt → DENIED
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/sso-audit-readonly-role` |
| Metadata download | GetSAMLProvider | `saml-provider/ProdOktaSSO` |
| SAML assumption denied | AssumeRoleWithSAML (failure) | `role/prod-okta-admin-role` |

---

## Scenario 16 — Resource Tags Breadcrumb Trail

**Role**: `resource-inventory-readonly-role` · **Folder**: `scenario-18` · **Cost**: $0.00/mo

Resources are tagged with references to other resources creating a breadcrumb trail. The primary detection signal is the role assumption itself.

```
Attacker → AssumeRole → follows breadcrumb tags to other resources
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/resource-inventory-readonly-role` |

---

## Scenario 17 — Lambda + DynamoDB Enriched User PII

**Role**: `etl-ops-readonly-role` · **Folder**: `scenario-19` · **Cost**: $0.00/mo

Attacker reads Lambda function `prod-user-data-enrichment` env vars, then scans the DynamoDB table for enriched user profiles.

```
Attacker → AssumeRole → GetFunctionConfiguration → Scan (enriched PII)
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/etl-ops-readonly-role` |
| Lambda config read | GetFunctionConfiguration | `function:prod-user-data-enrichment` |
| Table describe | DescribeTable | `table/prod-enriched-user-profiles` |
| DynamoDB scan | Scan | `table/prod-enriched-user-profiles` |

---

## Scenario 18 — SSM Parameter Cross-Reference Chain

**Role**: `infra-params-readonly-role` · **Folder**: `scenario-20` · **Cost**: $0.00/mo

Five SSM parameters under `/prod/db/*` cross-reference each other via `see_also` fields, creating a breadcrumb chain.

```
/prod/db/primary → /prod/db/replica → /prod/db/backup-config
                                           → /prod/db/encryption-config → /prod/db/monitoring
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/infra-params-readonly-role` |
| Chain reads (×5) | GetParameter | `parameter/prod/db/primary`, `replica`, `backup-config`, `encryption-config`, `monitoring` |
| Bulk read | GetParametersByPath | `parameter/prod/db` |

---

## Scenario 19 — CloudFormation Stack Outputs with Exposed Secrets

**Role**: `cfn-audit-readonly-role` · **Folder**: `scenario-21` · **Cost**: $0.00/mo

Stack `prod-core-infrastructure` exposes fake database passwords, API keys, Redis auth tokens, and admin URLs in its outputs.

```
Attacker → AssumeRole → DescribeStacks (reads outputs with secrets)
```

| Monitored Event | CloudTrail Event | Resource |
|----------------|-----------------|----------|
| Role assumption | AssumeRole | `role/cfn-audit-readonly-role` |
| Stack output read | DescribeStacks | `stack/prod-core-infrastructure` |

---

## Consolidated Detection Rules

### Lure Roles — Monitor AssumeRole

| # | Role Name |
|---|-----------|
| 1 | `infra-s3-data-readonly-role` |
| 2 | `payment-secrets-readonly-role` |
| 3 | `infra-config-readonly-role` |
| 4 | `devops-s3-deploy-role` |
| 5 | `prod-bastion-ecr-role` |
| 6 | `lambda-ops-readonly-role` |
| 7 | `compliance-audit-readonly-role`, `prod-compliance-data-access-role` |
| 8 | `prod-microservice-auth-role`, `prod-microservice-data-role`, `prod-microservice-admin-role` |
| 9 | `customer-data-readonly-role` |
| 10 | `session-store-readonly-role` |
| 11 | `payment-queue-readonly-role` |
| 12 | `alerts-readonly-role` |
| 13 | `log-analysis-readonly-role` |
| 14 | `kms-audit-readonly-role` |
| 15 | `sso-audit-readonly-role` |
| 16 | `resource-inventory-readonly-role` |
| 17 | `etl-ops-readonly-role` |
| 18 | `infra-params-readonly-role` |
| 19 | `cfn-audit-readonly-role` |

### Lure Resources — Monitor Resource-Specific API Calls

| # | Resource | Monitored API Calls |
|---|----------|-------------------|
| 1 | `s3:::infra-terraform-state-<acct>` | GetObject |
| 2 | `secret:prod/payment-gateway/*`, `secret:prod/internal-api/*` | GetSecretValue |
| 3 | `parameter/prod/database/*`, `parameter/prod/ci-cd/*`, `parameter/prod/monitoring/*`, `parameter/prod/vpn/*`, `parameter/prod/kubernetes/*` | GetParameter, GetParametersByPath |
| 4 | `devops-deploy-keys-<acct>`, `instance/<id>`, `security-group/<id>` | GetObject, StartInstances, AuthorizeSecurityGroupIngress |
| 5 | `repository/prod-payment-service` | BatchGetImage, GetDownloadUrlForLayer |
| 6 | `function:prod-data-sync-processor`, `prod-data-sync-artifacts-<acct>`, `secret:prod/data-sync/*`, `parameter/prod/data-sync/*` | GetFunctionConfiguration, GetObject, GetSecretValue, GetParameter |
| 7 | `function:prod-compliance-report-generator`, `compliance-audit-reports-<acct>`, `secret:prod/compliance/*`, `parameter/prod/compliance/*` | GetFunctionConfiguration, GetObject, GetSecretValue, GetParameter |
| 8 | `parameter/prod/auth/*`, `parameter/prod/data/*`, `parameter/prod/admin/*` | GetParameter |
| 9 | `table/prod-customer-profiles` | DescribeTable, Scan, Query, GetItem |
| 10 | `table/prod-active-sessions` | DescribeTable, Scan, Query |
| 11 | `prod-payment-events-dlq.fifo` | GetQueueAttributes, ReceiveMessage |
| 12 | `prod-alerts-critical` | GetTopicAttributes, ListSubscriptionsByTopic, Publish |
| 13 | `log-group:/prod/payment-service/application` | GetLogEvents, FilterLogEvents |
| 14 | `key/<key-id>` (`alias/prod-customer-data-encryption`) | DescribeKey, Decrypt |
| 15 | `saml-provider/ProdOktaSSO`, `role/prod-okta-admin-role` | GetSAMLProvider, AssumeRoleWithSAML |
| 16 | (role assumption is the primary signal) | — |
| 17 | `function:prod-user-data-enrichment`, `table/prod-enriched-user-profiles` | GetFunctionConfiguration, DescribeTable, Scan |
| 18 | `parameter/prod/db/*` | GetParameter, GetParametersByPath |
| 19 | `stack/prod-core-infrastructure` | DescribeStacks |

---

## Cost Summary

| Category | Scenarios | Monthly Cost |
|----------|-----------|-------------|
| Free tier (IAM, SSM Standard, DynamoDB, SQS, SNS, CW Logs, CFN, Tags) | 1, 8-13, 15-19 | $0.00 |
| Secrets Manager ($0.40/secret) | 2 (×3), 6 (×1), 7 (×1) | $2.00 |
| SSM Advanced (kubeconfig) | 3 | $0.05 |
| EC2 stopped (EBS only) | 4 | $0.64 |
| ECR storage | 5 | $0.01 |
| KMS key | 14 | $1.00 |
| **Total** | **19 scenarios** | **~$3.70/month** |

---

## Folder Mapping

| Doc # | Folder | Name |
|-------|--------|------|
| 1 | `scenario-1` | Terraform State Lure |
| 2 | `scenario-2` | Payment Credentials |
| 3 | `scenario-3` | Infrastructure Vault |
| 4 | `scenario-4` | SSH Key → EC2 Bastion |
| 5 | `scenario-5` | ECR Container Image |
| 6 | `scenario-6` | Lambda Data Sync |
| 7 | `scenario-7` | Lambda Role Chaining |
| 8 | `scenario-8` | Role Chain Loop |
| 9 | `scenario-9` | Customer Profiles |
| 10 | `scenario-10` | Active Sessions |
| 11 | `scenario-11` | Payment Events DLQ |
| 12 | `scenario-12` | Critical Alerts |
| 13 | `scenario-13` | Leaked Logs |
| 14 | `scenario-14` | Encryption Key |
| 15 | `scenario-15` | Fake SSO |
| 16 | `scenario-16` | Tag Breadcrumbs |
| 17 | `scenario-17` | Enriched User PII |
| 18 | `scenario-18` | SSM Chain |
| 19 | `scenario-19` | Stack Outputs |

---

## Deployment

Each scenario is self-contained in its folder with:

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template |
| `deploy.sh` | One-command deploy + data seeding |
| `abuse.sh` | Attack simulation script with colored output |
| `fake-data/` | Seed data files (JSON, CSV, YAML) |
| `README.md` | Scenario documentation |
| `PROMPT.md` | Original scenario specification |

### Deploy a scenario

```bash
cd scenarios/scenario-N
chmod +x deploy.sh
./deploy.sh
```

### Simulate the attack

```bash
chmod +x abuse.sh
./abuse.sh
```

### Teardown

```bash
# For scenarios with S3 buckets, empty the bucket first
aws s3 rm s3://<bucket-name> --recursive
aws cloudformation delete-stack --stack-name deception-scenario-N --region us-west-2
```
