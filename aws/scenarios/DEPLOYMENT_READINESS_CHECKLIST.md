# Deployment Readiness Checklist — All Scenarios

This document provides a per-scenario deployment readiness review covering:
- What it does
- Internal-only verification
- What's intended
- Cost

---

## Scenario 1 — S3 Terraform State Lure

**Folder:** `scenario-1` | **Stack:** `deception-scenario-1`

### What It Does
Deploys an IAM role (`infra-s3-data-readonly-role`) and an S3 bucket (`infra-terraform-state-<acct>`) containing a fake Terraform state file with RDS credentials, Stripe keys, IAM access keys, Redis tokens, and DB connection strings.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| S3 public access blocked (all 4 settings) | ✅ |
| S3 bucket policy: account root only | ✅ |
| TLS-only enforced (deny insecure transport) | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Encryption enabled (AES256 + BucketKey) | ✅ |
| Versioning enabled | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to download tfstate | S3 bucket with realistic name + path |
| Detect role assumption | CloudTrail: AssumeRole |
| Detect state file access | CloudTrail: GetObject |
| No real credentials exposed | All values are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| S3 storage (~50KB) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 2 — Payment Credentials (Secrets Manager)

**Folder:** `scenario-2` | **Stack:** `deception-scenario-2`

### What It Does
Deploys an IAM role (`payment-secrets-readonly-role`) and 3 Secrets Manager secrets containing fake Stripe keys, Braintree credentials, and internal service account API keys.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| Secret resource policies: account root only | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Secrets encrypted (AWS-managed KMS) | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to read payment secrets | 3 secrets with realistic names under prod/ |
| Detect secret reads | CloudTrail: GetSecretValue × 3 |
| No real credentials exposed | All payment keys are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| Secrets Manager (3 × $0.40) | $1.20 |
| IAM resources | $0.00 |
| **Total** | **$1.20** |

---

## Scenario 3 — Infrastructure Vault (SSM Parameter Store)

**Folder:** `scenario-3` | **Stack:** `deception-scenario-3`

### What It Does
Deploys an IAM role (`infra-config-readonly-role`) and 5 SSM parameters under `/prod/*` containing fake database credentials, GitHub deploy token, Datadog API keys, VPN admin credentials, and EKS kubeconfig.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| SSM parameters: no resource policy (not supported) | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Parameters scoped to specific ARNs in IAM policy | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to read infra params | 5 params with realistic paths |
| Detect parameter reads | CloudTrail: GetParameter, GetParametersByPath |
| No real credentials exposed | All values are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| SSM Standard (4 params) | $0.00 |
| SSM Advanced (1 param — kubeconfig >4KB) | $0.05 |
| IAM resources | $0.00 |
| **Total** | **$0.05** |

---

## Scenario 4 — SSH Key → EC2 Bastion

**Folder:** `scenario-4` | **Stack:** `deception-scenario-4`

### What It Does
Deploys an IAM role (`devops-s3-deploy-role`), S3 bucket with SSH private key, security group, and a stopped EC2 instance seeded with sensitive files. Attacker must modify SG, start instance, and SSH in.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| S3 public access blocked (all 4 settings) | ✅ |
| S3 bucket policy: account root only | ✅ |
| TLS-only enforced | ✅ |
| EC2 permissions scoped to specific instance ARN | ✅ |
| SG permissions scoped to specific SG ARN | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No instance profile (standalone) | ✅ |
| EBS encrypted | ✅ |
| SG restricts SSH to deployer CIDR | ✅ |
| Instance deployed stopped | ✅ |
| No Elastic IP | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Multi-step attack chain | S3 key → SG modify → start instance → SSH |
| Detect each attack step | 5 CloudTrail signals + VPC Flow Logs |
| Seeded files look real | .env, db-backup-creds, internal-hosts, AWS creds |
| No real credentials exposed | All values are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| EBS 8GB gp3 (persists while stopped) | $0.64 |
| EC2 t4g.nano (stopped) | $0.00 |
| S3 (single PEM file) | $0.00 |
| **Total** | **$0.64** |

---

## Scenario 5 — ECR Container Image

**Folder:** `scenario-5` | **Stack:** `deception-scenario-5`

### What It Does
Deploys an ECR repository (`prod-payment-service`) with a Docker image containing fake DB credentials, Stripe keys, PII records, and AWS session tokens. Optionally chains from Scenario 4 via instance profile.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust: ec2.amazonaws.com only (instance profile) | ✅ |
| ECR repo policy: account root only | ✅ |
| No public ECR access | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| Image tag immutability enabled | ✅ |
| Scan on push enabled | ✅ |
| ECR encryption (AES256) | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to pull container image | ECR repo with realistic name + tags |
| Image contains extractable secrets | .env, secrets.json (PII), AWS creds |
| Detect image pull | CloudTrail: BatchGetImage, GetDownloadUrlForLayer |
| Chain from Scenario 4 | Instance profile auto-attached to bastion |

### Cost
| Component | Monthly |
|-----------|---------|
| ECR storage (~50MB image) | $0.01 |
| IAM resources | $0.00 |
| **Total** | **$0.01** |

---

## Scenario 6 — Lambda Data Sync

**Folder:** `scenario-6` | **Stack:** `deception-scenario-6`

### What It Does
Deploys a Lambda function (`prod-data-sync-processor`) with secrets in environment variables. Discovery role can read config, update code, and invoke the function. The execution role pivots to S3, Secrets Manager, and SSM. Attacker can inject code to steal execution role credentials.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| Lambda execution role: lambda.amazonaws.com only | ✅ |
| S3 bucket policy: account root + TLS-only | ✅ |
| Secret resource policy: account root only | ✅ |
| No cross-account trust | ✅ |
| No public endpoints | ✅ |
| No IAM users created | ✅ |
| Discovery role Lambda actions scoped to specific function ARN | ✅ |
| Execution role scoped to specific S3/SM/SSM ARNs | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to read Lambda config | Env vars contain DB creds, Stripe key, Slack webhook |
| Enable credential theft via code injection | Discovery role has InvokeFunction + UpdateFunctionCode |
| Execution role pivots to more resources | S3 artifacts, Secrets Manager, SSM |
| Detect Lambda config read | CloudTrail: GetFunctionConfiguration |
| Detect code injection (critical signal) | CloudTrail: UpdateFunctionCode |
| Detect function invoke (critical signal) | CloudTrail: Invoke |
| Detect pivot reads | CloudTrail: GetObject, GetSecretValue, GetParameter |

### Cost
| Component | Monthly |
|-----------|---------|
| Secrets Manager (1 × $0.40) | $0.40 |
| S3 storage (2 small JSON files) | $0.00 |
| SSM Standard (1 param) | $0.00 |
| Lambda (never invoked in normal ops) | $0.00 |
| **Total** | **$0.40** |

---

## Scenario 7 — Lambda Role Chaining (Compliance)

**Folder:** `scenario-7` | **Stack:** `deception-scenario-7`

### What It Does
Deploys a Lambda function (`prod-compliance-report-generator`) with a `PIVOT_ROLE_ARN` env var. Attacker discovers the pivot role (`prod-compliance-data-access-role`) which reads S3 (PCI-DSS reports), Secrets Manager, and SSM.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| Discovery role trust: account root only | ✅ |
| Pivot role trust: account root only | ✅ |
| Lambda execution role: lambda.amazonaws.com only | ✅ |
| S3 bucket policy: account root only | ✅ |
| Secret resource policy: account root only | ✅ |
| No cross-account trust | ✅ |
| No public endpoints | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Multi-hop role chaining | Discovery → Lambda config → pivot role → data |
| Compliance-themed lure | PCI-DSS, SOX, PII export reports |
| Detect each hop | CloudTrail: AssumeRole × 2, GetFunctionConfiguration, GetObject, GetSecretValue, GetParameter |

### Cost
| Component | Monthly |
|-----------|---------|
| Secrets Manager (1 secret) | $0.40 |
| S3 storage | $0.00 |
| SSM Standard | $0.00 |
| Lambda (never invoked) | $0.00 |
| **Total** | **$0.40** |

---

## Scenario 8 — IAM Role Chain Loop

**Folder:** `scenario-9` | **Stack:** `deception-scenario-9`

### What It Does
Deploys 3 IAM roles in a circular chain (auth → data → admin → auth). Each role has an SSM parameter with themed credentials. Attacker gets trapped in the loop generating CloudTrail events.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| All role trusts: account root only | ✅ |
| SSM parameters: no resource policy | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Each role can only assume the next in chain | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Trap attacker in assumption loop | Circular chain A→B→C→A |
| Each hop reveals themed credentials | OIDC config, data lake creds, admin console creds |
| Detect every hop | CloudTrail: AssumeRole × 3+, GetParameter × 3 |

### Cost
| Component | Monthly |
|-----------|---------|
| SSM Standard (3 params) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 9 — DynamoDB Customer Profiles

**Folder:** `scenario-11` | **Stack:** `deception-scenario-11`

### What It Does
Deploys a DynamoDB table (`prod-customer-profiles`) seeded with fake PII records and an IAM role (`customer-data-readonly-role`) granting read access.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| DynamoDB: no resource policy (not supported) | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| DynamoDB permissions scoped to specific table ARN | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to scan PII table | DynamoDB with realistic customer records |
| Detect table access | CloudTrail: DescribeTable, Scan, Query |
| No real PII exposed | All records are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| DynamoDB on-demand (no traffic) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 10 — DynamoDB Active Sessions

**Folder:** `scenario-12` | **Stack:** `deception-scenario-12`

### What It Does
Deploys a DynamoDB table (`prod-active-sessions`) seeded with fake JWT tokens, session IDs, and refresh tokens. IAM role: `session-store-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| DynamoDB: no resource policy | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Permissions scoped to specific table ARN | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to steal session tokens | DynamoDB with realistic JWT/session records |
| Detect table access | CloudTrail: DescribeTable, Scan |
| No real tokens exposed | All JWTs are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| DynamoDB on-demand (no traffic) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 11 — SQS Payment Events DLQ

**Folder:** `scenario-13` | **Stack:** `deception-scenario-13`

### What It Does
Deploys SQS FIFO queues (main + DLQ: `prod-payment-events-dlq.fifo`) seeded with fake payment event messages. IAM role: `payment-queue-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| SQS queue policy: account root only | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Permissions scoped to specific queue ARNs | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to read payment messages | DLQ with fake card tokens and amounts |
| Detect queue access | CloudTrail: GetQueueAttributes, ReceiveMessage |
| No real payment data exposed | All transactions are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| SQS (no traffic) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 12 — SNS Critical Alerts

**Folder:** `scenario-14` | **Stack:** `deception-scenario-14`

### What It Does
Deploys an SNS topic (`prod-alerts-critical`) with subscriptions pointing to fake internal webhook URLs and email addresses. IAM role: `alerts-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| SNS topic policy: account root only | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| Subscription endpoints are non-existent internal URLs | ✅ |
| No real notifications sent | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to enumerate alert infrastructure | SNS topic with realistic subscriptions |
| Detect topic access | CloudTrail: GetTopicAttributes, ListSubscriptionsByTopic, Publish |
| No real alerts triggered | Endpoints don't exist |

### Cost
| Component | Monthly |
|-----------|---------|
| SNS (no traffic) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 13 — CloudWatch Logs with Leaked Credentials

**Folder:** `scenario-15` | **Stack:** `deception-scenario-15`

### What It Does
Deploys a CloudWatch log group (`/prod/payment-service/application`) with seeded log entries containing "accidentally logged" credentials. IAM role: `log-analysis-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| CloudWatch Logs: no resource policy needed | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Permissions scoped to specific log group ARN | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to search logs for creds | Log entries with DB strings, API keys in stack traces |
| Detect log reads | CloudTrail: GetLogEvents, FilterLogEvents |
| No real credentials exposed | All values are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| CloudWatch Logs (minimal storage) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 14 — KMS Encryption Key

**Folder:** `scenario-16` | **Stack:** `deception-scenario-16`

### What It Does
Deploys a KMS key (`alias/prod-customer-data-encryption`) with describe/list allowed but decrypt explicitly denied. IAM role: `kms-audit-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| KMS key policy: account root admin | ✅ |
| Decrypt explicitly denied for lure role | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| Key rotation enabled | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to investigate encryption key | Realistic key with alias and grants |
| Detect key inspection | CloudTrail: DescribeKey |
| Detect decrypt attempt (denied) | CloudTrail: Decrypt (failure) |
| No data can be decrypted | Explicit deny on Decrypt |

### Cost
| Component | Monthly |
|-----------|---------|
| KMS key (1 CMK) | $1.00 |
| IAM resources | $0.00 |
| **Total** | **$1.00** |

---

## Scenario 15 — SAML Provider (Fake Okta SSO)

**Folder:** `scenario-17` | **Stack:** `deception-scenario-17`

### What It Does
Deploys a SAML provider (`ProdOktaSSO`) with metadata XML and SAML-trusted roles that cannot be assumed without a valid SAML assertion. IAM role: `sso-audit-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| Discovery role trust: account root only | ✅ |
| SAML roles: require valid SAML assertion (cannot be assumed) | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No real IdP integration | ✅ |
| SAML metadata is self-signed/fabricated | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to investigate SSO config | SAML provider with realistic Okta metadata |
| Detect metadata download | CloudTrail: GetSAMLProvider |
| Detect assumption attempt (denied) | CloudTrail: AssumeRoleWithSAML (failure) |
| No real SSO access possible | SAML assertion required |

### Cost
| Component | Monthly |
|-----------|---------|
| SAML provider | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 16 — Resource Tags Breadcrumb Trail

**Folder:** `scenario-18` | **Stack:** `deception-scenario-18`

### What It Does
Deploys resources tagged with ARNs and S3 URIs referencing other resources, creating a breadcrumb trail. IAM role: `resource-inventory-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Tags reference internal resources only | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to follow tag breadcrumbs | Tags reference other lure resources |
| Primary detection: role assumption | CloudTrail: AssumeRole |
| Breadcrumbs lead to other scenarios | Cross-references create engagement |

### Cost
| Component | Monthly |
|-----------|---------|
| SSM Standard params | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 17 — Lambda + DynamoDB Enriched User PII

**Folder:** `scenario-19` | **Stack:** `deception-scenario-19`

### What It Does
Deploys a Lambda function (`prod-user-data-enrichment`) with env var API keys and a DynamoDB table (`prod-enriched-user-profiles`) with enriched PII. IAM role: `etl-ops-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| Lambda execution role: lambda.amazonaws.com only | ✅ |
| DynamoDB: no resource policy | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Permissions scoped to specific function + table ARNs | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to read Lambda config + scan PII | Lambda env vars + DynamoDB records |
| Detect Lambda read | CloudTrail: GetFunctionConfiguration |
| Detect table scan | CloudTrail: DescribeTable, Scan |
| No real PII exposed | All records are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| Lambda (never invoked) | $0.00 |
| DynamoDB on-demand (no traffic) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 18 — SSM Parameter Cross-Reference Chain

**Folder:** `scenario-20` | **Stack:** `deception-scenario-20`

### What It Does
Deploys 5 SSM parameters under `/prod/db/*` that cross-reference each other via `see_also` fields, creating a breadcrumb chain. IAM role: `infra-params-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| SSM parameters: no resource policy | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| Permissions scoped to /prod/db/* path | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to follow parameter chain | 5 params cross-referencing each other |
| Detect parameter reads | CloudTrail: GetParameter × 5, GetParametersByPath |
| No real credentials exposed | All DB configs are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| SSM Standard (5 params) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Scenario 19 — CloudFormation Stack Outputs

**Folder:** `scenario-21` | **Stack:** `deception-scenario-21`

### What It Does
Deploys a CloudFormation stack (`prod-core-infrastructure`) that exposes fake database passwords, API keys, Redis auth tokens, and admin URLs in its outputs. IAM role: `cfn-audit-readonly-role`.

### Internal-Only Verification

| Check | Status |
|-------|--------|
| IAM trust scoped to account root only | ✅ |
| No cross-account trust | ✅ |
| No IAM users created | ✅ |
| No public endpoints | ✅ |
| CFN permissions scoped to specific stack | ✅ |
| Stack outputs contain only fabricated values | ✅ |

### What's Intended

| Intent | Implementation |
|--------|---------------|
| Lure attacker to read stack outputs | Outputs with realistic secret values |
| Detect stack inspection | CloudTrail: DescribeStacks |
| No real credentials exposed | All output values are fabricated |

### Cost
| Component | Monthly |
|-----------|---------|
| SSM Standard params (backing resources) | $0.00 |
| IAM resources | $0.00 |
| **Total** | **$0.00** |

---

## Cost Summary

| # | Scenario | Monthly Cost |
|---|----------|-------------|
| 1 | Terraform State Lure | $0.00 |
| 2 | Payment Credentials | $1.20 |
| 3 | Infrastructure Vault | $0.05 |
| 4 | SSH Key → EC2 Bastion | $0.64 |
| 5 | ECR Container Image | $0.01 |
| 6 | Lambda Data Sync | $0.40 |
| 7 | Lambda Role Chaining | $0.40 |
| 8 | Role Chain Loop | $0.00 |
| 9 | Customer Profiles | $0.00 |
| 10 | Active Sessions | $0.00 |
| 11 | Payment Events DLQ | $0.00 |
| 12 | Critical Alerts | $0.00 |
| 13 | Leaked Logs | $0.00 |
| 14 | Encryption Key | $1.00 |
| 15 | Fake SSO | $0.00 |
| 16 | Tag Breadcrumbs | $0.00 |
| 17 | Enriched User PII | $0.00 |
| 18 | SSM Chain | $0.00 |
| 19 | Stack Outputs | $0.00 |
| | **TOTAL** | **~$3.70/mo** |

---

## Global Security Guarantees (All Scenarios)

| Guarantee | Status |
|-----------|--------|
| No public access on any resource | ✅ |
| No cross-account trust policies | ✅ |
| No IAM users created (roles only) | ✅ |
| No real credentials or PII | ✅ |
| No `FAKE`/`EXPIRED`/`REVOKED` labels in data | ✅ |
| All roles: MaxSessionDuration = 3600s | ✅ |
| All roles: account root trust only (except ec2.amazonaws.com for scenario 5) | ✅ |
| Encryption enabled where supported | ✅ |
| Least privilege IAM (scoped to specific resource ARNs) | ✅ |

---

## Deploy Order (Recommended)

```bash
# Independent scenarios (any order)
cd scenario-1  && ./deploy.sh
cd scenario-2  && ./deploy.sh
cd scenario-3  && ./deploy.sh
cd scenario-9  && ./deploy.sh   # Role Chain Loop
cd scenario-11 && ./deploy.sh   # Customer Profiles
cd scenario-12 && ./deploy.sh   # Active Sessions
cd scenario-13 && ./deploy.sh   # Payment Events DLQ
cd scenario-14 && ./deploy.sh   # Critical Alerts
cd scenario-15 && ./deploy.sh   # Leaked Logs
cd scenario-16 && ./deploy.sh   # KMS Key
cd scenario-17 && ./deploy.sh   # Fake SSO
cd scenario-18 && ./deploy.sh   # Tag Breadcrumbs
cd scenario-19 && ./deploy.sh   # Enriched User PII
cd scenario-20 && ./deploy.sh   # SSM Chain
cd scenario-21 && ./deploy.sh   # Stack Outputs

# Dependent scenarios (deploy in order)
cd scenario-4  && ./deploy.sh   # EC2 Bastion (first)
cd scenario-5  && ./deploy.sh   # ECR (chains to scenario-4)
cd scenario-6  && ./deploy.sh   # Lambda Data Sync
cd scenario-7  && ./deploy.sh   # Lambda Role Chaining
```
