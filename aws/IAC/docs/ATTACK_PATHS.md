# Cloud Deception — Attack Paths

## Overview

Internal deception infrastructure deployed to detect insider threats and compromised identities within the AWS account. Each scenario creates realistic lure resources that generate high-fidelity CloudTrail detection signals when interacted with. All credentials and data are completely fabricated.

| Property | Value |
|----------|-------|
| Region | us-west-2 |
| Total Scenarios | 19 |
| Total Monthly Cost | ~$3.70 |
| Monitoring Cost | $0.00 (uses existing CloudTrail) |
| IaC | CloudFormation |
| Access Model | Internal account only (root principal) |

---

## Design Principles

### No Public Access
Every resource has public access fully blocked. S3 buckets have all four PublicAccessBlock settings enabled, bucket policies enforce TLS-only, and no resource is accessible from outside the account. The only exception is the EC2 bastion in Scenario 4, which requires a public IP for the SSH lure — but the security group restricts inbound to a deployer-specified CIDR, and the instance is deployed stopped.

### No Cross-Account Access
No external account references or cross-account trust policies exist anywhere in the infrastructure. All IAM role trust policies reference only `arn:aws:iam::<AccountId>:root` (same account) or AWS service principals (`lambda.amazonaws.com`, `ec2.amazonaws.com`). No resource policy grants access to external accounts.

### No IAM Users
Only IAM roles are used throughout. No IAM users, access keys, or long-lived credentials are created. This follows AWS security best practices and ensures all access is temporary, auditable, and revocable.

### Least Privilege
Each role only gets the exact permissions the scenario requires. Discovery roles are scoped to specific resource ARNs wherever AWS supports it. List/Describe actions use `Resource: *` only where AWS mandates it (e.g., `ListFunctions`, `ListTables`, `ListBuckets`). Write permissions are never granted unless the scenario specifically requires it for the attack path (e.g., Scenario 7 code injection).

### No Giveaway Labels
No `FAKE`, `EXPIRED`, `REVOKED`, `TEST`, `HONEYPOT`, or `DECEPTION` labels appear in any resource name, tag value, credential, or data content. Everything looks legitimate and production-grade. Tags use realistic values: `Environment=production`, `ManagedBy=terraform`, `Project=<realistic-team-name>`.

### Look-Alike Naming Convention
Every resource is named with conventions matching legitimate production resources in the account. Role names follow patterns like `<team>-<function>-readonly-role`, bucket names use `<purpose>-<account-id>`, and parameters use paths like `/prod/<service>/<config-name>`. An attacker enumerating resources cannot distinguish lures from real infrastructure by name alone.

### SCP Protection for Deception Resources
An Organization Service Control Policy (SCP) should be applied to restrict deletion of deception resources to only authorized security team members. This prevents an attacker who gains elevated access from removing the lures to cover their tracks, and prevents accidental deletion by other teams.

Recommended SCP structure:
- Deny `cloudformation:DeleteStack` on deception stack names for all principals except the security team role
- Deny `iam:DeleteRole` on lure role names for all principals except the security team role
- Deny `s3:DeleteBucket` on lure bucket names for all principals except the security team role

This ensures only designated operators can deploy, modify, or tear down the deception infrastructure.

### Internal Identification (Without Standing Out)
Deception resources do not carry any tag that explicitly identifies them as lures. Instead, identification relies on a shared tag value known only to the security team — such as a specific `CostCenter` code or a unique `Project` value. This allows the team to query and inventory all deception resources (e.g., via Resource Groups or AWS Config) without revealing their nature to an attacker who enumerates tags.

The attacker sees `CostCenter=CC-7200` and assumes it belongs to a real team. The security team knows that CC-7200 is reserved for deception infrastructure. No additional "deception" or "honeypot" tags are used.

> **Note:** The resource names used in these scenarios are for POC purposes only. In the Pilot Phase, all resources will be renamed to match the specific naming conventions of the target account they are deployed into, ensuring they blend seamlessly with legitimate infrastructure.

---

## Quick Reference

| # | Name | Entry Role | Lure Type | Key Signal | Cost/mo |
|---|------|-----------|-----------|------------|---------|
| 1 | Terraform State | infra-s3-data-readonly-role | S3 + fake tfstate | GetObject | $0.00 |
| 2 | Payment Credentials | payment-secrets-readonly-role | Secrets Manager (×3) | GetSecretValue | $1.20 |
| 3 | Infrastructure Vault | infra-config-readonly-role | SSM Parameters (×5) | GetParameter | $0.05 |
| 4 | SSH Key → EC2 Bastion | devops-s3-deploy-role | S3 + EC2 + SG | StartInstances | $0.64 |
| 5 | ECR Container Image | prod-bastion-ecr-role | ECR Docker image | BatchGetImage | $0.01 |
| 6 | Lambda Blueprint | lambda-ops-readonly-role | Lambda env vars | GetFunctionConfiguration | $0.00 |
| 7 | Lambda Code Injection | lambda-ops-readonly-role (linked) | Lambda code update | UpdateFunctionCode | $0.00 |
| 8 | Lambda Role Chaining | compliance-audit-readonly-role | Lambda → pivot role | AssumeRole (pivot) | $0.40 |
| 9 | Role Chain Loop | prod-microservice-auth-role | 3 roles in circle | AssumeRole (×3+) | $0.00 |
| 11 | Customer Data | customer-data-readonly-role | DynamoDB (×2 tables) | Scan | $0.00 |
| 13 | Payment Events DLQ | payment-queue-readonly-role | SQS FIFO DLQ | ReceiveMessage | $0.00 |
| 14 | Critical Alerts | alerts-readonly-role | SNS topic + subs | GetTopicAttributes | $0.00 |
| 15 | Leaked Logs | log-analysis-readonly-role | CloudWatch Logs | GetLogEvents | $0.00 |
| 16 | Encryption Key | kms-audit-readonly-role | KMS CMK (deny decrypt) | DescribeKey / Decrypt (denied) | $1.00 |
| 17 | Fake SSO (Okta) | sso-audit-readonly-role | SAML provider + roles | GetSAMLProvider | $0.00 |
| 18 | Tag Breadcrumbs | resource-inventory-readonly-role | Resource tags | AssumeRole | $0.00 |
| 19 | Enriched User PII | etl-ops-readonly-role | Lambda + DynamoDB | GetFunctionConfiguration | $0.00 |
| 20 | SSM Chain | infra-params-readonly-role | SSM cross-references (×5) | GetParameter (×5) | $0.00 |
| 21 | Stack Outputs | cfn-audit-readonly-role | CFN outputs with secrets | DescribeStacks | $0.00 |

---

## Attack Paths

---

### Scenario 1 — Terraform State Lure

An attacker assumes a role granting S3 read access and discovers a bucket named `infra-terraform-state-<account-id>`. Inside, they find a Terraform state file containing what appears to be live RDS credentials, Stripe API keys, IAM access keys, and Redis auth tokens. All values are fabricated.

**Attack Path:**
1. `sts:AssumeRole` → `infra-s3-data-readonly-role`
2. `s3:ListAllMyBuckets` → discovers `infra-terraform-state-<acct>`
3. `s3:GetObject` → downloads `env/production/terraform.tfstate`
4. Extracts credentials → attempts to use them → triggers alerts

**AWS Services:** IAM, S3

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/infra-s3-data-readonly-role | High |
| GetObject | infra-terraform-state-<acct>/env/production/terraform.tfstate | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 2 — Payment Credentials

An attacker assumes a role and reads three Secrets Manager secrets containing what appear to be live Stripe API keys, Braintree merchant credentials, and internal service account API keys. The realistic naming and credential formats lure the attacker into attempting to use them.

**Attack Path:**
1. `sts:AssumeRole` → `payment-secrets-readonly-role`
2. `secretsmanager:ListSecrets` → discovers payment-related secrets
3. `secretsmanager:GetSecretValue` × 3 → reads Stripe, Braintree, service accounts
4. Attempts to use credentials → triggers alerts

**AWS Services:** IAM, Secrets Manager

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/payment-secrets-readonly-role | High |
| GetSecretValue | secret:prod/payment-gateway/stripe-keys | Critical |
| GetSecretValue | secret:prod/payment-gateway/braintree-credentials | Critical |
| GetSecretValue | secret:prod/internal-api/service-accounts | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $1.20/mo (3 secrets × $0.40)

---

### Scenario 3 — Infrastructure Vault

An attacker reads SSM parameters under `/prod/*` containing database master credentials, a GitHub deploy token, Datadog API keys, VPN admin credentials, and an EKS cluster-admin kubeconfig. The breadth of credentials makes this look like a central infrastructure secrets store.

**Attack Path:**
1. `sts:AssumeRole` → `infra-config-readonly-role`
2. `ssm:DescribeParameters` → discovers parameters under /prod/
3. `ssm:GetParametersByPath` or `ssm:GetParameter` × 5 → reads all credentials
4. Attempts lateral movement with extracted creds → triggers alerts

**AWS Services:** IAM, SSM Parameter Store

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/infra-config-readonly-role | High |
| GetParametersByPath | parameter/prod | Critical |
| GetParameter | parameter/prod/database/master-credentials | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.05/mo (1 Advanced parameter for kubeconfig >4KB)

---

### Scenario 4 — SSH Key → EC2 Bastion

An attacker downloads an SSH private key from S3, modifies a security group to allow their IP, starts a stopped EC2 instance, and SSHs in to find sensitive files on disk. This is the most complex multi-step scenario with 5 distinct detection signals.

**Attack Path:**
1. `sts:AssumeRole` → `devops-s3-deploy-role`
2. `s3:GetObject` → downloads `keys/prod-bastion-keypair.pem`
3. `ec2:DescribeInstances` → finds stopped `prod-bastion-host`
4. `ec2:AuthorizeSecurityGroupIngress` → adds attacker IP to SG ⚠️
5. `ec2:StartInstances` → boots the instance ⚠️
6. SSH in → finds .env, db-backup-creds, internal-hosts, AWS credentials

**AWS Services:** IAM, S3, EC2, Security Groups

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/devops-s3-deploy-role | High |
| GetObject | devops-deploy-keys-<acct>/keys/prod-bastion-keypair.pem | Critical |
| AuthorizeSecurityGroupIngress | security-group/<sg-id> | Critical |
| StartInstances | instance/<instance-id> | Critical |
| SSH connection (VPC Flow Logs) | bastion public IP, port 22 | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.64/mo (EBS volume persists while stopped)

---

### Scenario 5 — ECR Container Image

An attacker authenticates to ECR and pulls a Docker image named `prod-payment-service` containing database credentials, Stripe keys, PII records, and AWS session tokens baked into the filesystem. Chains from Scenario 4 via instance profile.

**Attack Path:**
1. Instance profile on bastion → `prod-bastion-ecr-role`
2. `ecr:GetAuthorizationToken` → authenticates Docker to ECR
3. `ecr:BatchGetImage` + `GetDownloadUrlForLayer` → pulls image
4. Inspects image layers → extracts .env, secrets.json, AWS credentials

**AWS Services:** IAM, ECR

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| BatchGetImage | repository/prod-payment-service | Critical |
| GetDownloadUrlForLayer | repository/prod-payment-service | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.01/mo (ECR storage ~50MB)

---

### Scenario 6 — Lambda Blueprint (Read-Only Recon)

An attacker reads a Lambda function's configuration and extracts hardcoded secrets from environment variables: database credentials, Stripe API key, Slack webhook, and encryption key. This is the base module that Scenarios 7 and 8 can link to.

**Attack Path:**
1. `sts:AssumeRole` → `lambda-ops-readonly-role`
2. `lambda:ListFunctions` → discovers `prod-data-sync-processor`
3. `lambda:GetFunctionConfiguration` → extracts env var secrets
4. Notes execution role ARN and S3 bucket name for further investigation

**AWS Services:** IAM, Lambda, S3 (optional), Secrets Manager (optional), SSM (optional)

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/lambda-ops-readonly-role | High |
| GetFunctionConfiguration | function:prod-data-sync-processor | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo (or $0.40 if Secrets Manager included)

---

### Scenario 7 — Lambda Code Injection

An attacker updates a Lambda function's code with a credential-exfiltration payload, invokes it, and receives the execution role's temporary ASIA session credentials. They then use those to access S3, Secrets Manager, and SSM. Links to Scenario 6 or deploys standalone.

**Attack Path:**
1. `sts:AssumeRole` → discovery role
2. `lambda:GetFunctionConfiguration` → reads env vars + exec role ARN
3. `lambda:UpdateFunctionCode` → injects exfil payload ⚠️
4. `lambda:InvokeFunction` → receives ASIA credentials ⚠️
5. Uses stolen creds → accesses S3, SM, SSM
6. Restores original code (cleanup attempt)

**AWS Services:** IAM, Lambda

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/lambda-ops-readonly-role | High |
| GetFunctionConfiguration | function:prod-data-sync-processor | High |
| UpdateFunctionCode | function:prod-data-sync-processor | Critical |
| Invoke | function:prod-data-sync-processor | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 8 — Lambda Role Chaining (Compliance Pivot)

An attacker reads a Lambda function's configuration and discovers a `PIVOT_ROLE_ARN` environment variable pointing to a role with compliance data access. Unlike the execution role, this pivot role is directly assumable by any account principal. The attacker assumes it and reads PCI-DSS reports, encryption keys, and database credentials.

**Attack Path:**
1. `sts:AssumeRole` → discovery role
2. `lambda:GetFunctionConfiguration` → finds `PIVOT_ROLE_ARN` in env vars
3. `sts:AssumeRole` → `prod-compliance-data-access-role` (directly assumable) ⚠️
4. Reads S3 compliance reports, Secrets Manager encryption keys, SSM DB credentials

**AWS Services:** IAM, Lambda, S3, Secrets Manager, SSM

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | discovery role | High |
| GetFunctionConfiguration | Lambda function | High |
| AssumeRole | role/prod-compliance-data-access-role | Critical |
| GetObject | compliance-audit-reports-<acct>/* | High |
| GetSecretValue | secret:prod/compliance/encryption-keys | High |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.40/mo (1 Secrets Manager secret)

---

### Scenario 9 — Role Chain Loop

Three IAM roles assume each other in a circular chain (auth → data → admin → auth). Each role has an SSM parameter with themed credentials. The attacker gets trapped in the loop, generating a minimum of 6 CloudTrail events per full cycle.

**Attack Path:**
1. `sts:AssumeRole` → `prod-microservice-auth-role` (entry)
2. `ssm:GetParameter` → reads OIDC config
3. `sts:AssumeRole` → `prod-microservice-data-role`
4. `ssm:GetParameter` → reads data lake credentials
5. `sts:AssumeRole` → `prod-microservice-admin-role`
6. `ssm:GetParameter` → reads admin console credentials
7. Sees: can assume auth-role again → LOOP

**AWS Services:** IAM (×3 roles), SSM (×3 parameters)

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole (×3+) | auth-role, data-role, admin-role | High |
| GetParameter (×3) | /prod/auth/*, /prod/data/*, /prod/admin/* | High |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 11 — Customer Data (Profiles + Sessions)

An attacker scans two DynamoDB tables: one with fake customer PII (names, emails, phones, card tokens) and another with fake active sessions (JWTs, refresh tokens, IPs). The realistic data lures the attacker into attempting session hijacking or identity theft.

**Attack Path:**
1. `sts:AssumeRole` → `customer-data-readonly-role`
2. `dynamodb:ListTables` → discovers both tables
3. `dynamodb:Scan` → dumps customer profiles (12 PII records)
4. `dynamodb:Scan` → dumps active sessions (9 JWT records)
5. Attempts to use card tokens or replay JWTs → triggers alerts

**AWS Services:** IAM, DynamoDB (×2 tables)

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/customer-data-readonly-role | High |
| DescribeTable | table/prod-customer-profiles | High |
| Scan | table/prod-customer-profiles | Critical |
| Scan | table/prod-active-sessions | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 13 — Payment Events DLQ

An attacker reads messages from an SQS FIFO dead letter queue containing fake failed payment events with card tokens, transaction amounts, and internal service endpoint URLs exposed in error messages.

**Attack Path:**
1. `sts:AssumeRole` → `payment-queue-readonly-role`
2. `sqs:ListQueues` → discovers payment queues
3. `sqs:GetQueueAttributes` → sees message count, redrive policy
4. `sqs:ReceiveMessage` → reads failed payment events from DLQ
5. Extracts card tokens and internal endpoints → attempts to probe them

**AWS Services:** IAM, SQS FIFO (×2 queues)

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/payment-queue-readonly-role | High |
| GetQueueAttributes | prod-payment-events-dlq.fifo | High |
| ReceiveMessage | prod-payment-events-dlq.fifo | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 14 — Critical Alerts (SNS)

An attacker discovers an SNS topic with subscriptions pointing to an internal webhook URL and SRE on-call email. The subscriptions are PendingConfirmation so no real notifications are ever delivered.

**Attack Path:**
1. `sts:AssumeRole` → `alerts-readonly-role`
2. `sns:ListTopics` → discovers `prod-alerts-critical`
3. `sns:GetTopicAttributes` → reads topic config
4. `sns:ListSubscriptionsByTopic` → reveals internal webhook + SRE email
5. Attacker probes webhook URL or phishes email → triggers external detection

**AWS Services:** IAM, SNS

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/alerts-readonly-role | High |
| GetTopicAttributes | prod-alerts-critical | High |
| ListSubscriptionsByTopic | prod-alerts-critical | High |
| Publish (if attempted) | prod-alerts-critical | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 15 — Leaked Logs

An attacker reads CloudWatch log entries from a payment service log group and finds credentials "accidentally" logged in stack traces, HTTP debug headers, failed auth messages, and bootstrap environment dumps.

**Attack Path:**
1. `sts:AssumeRole` → `log-analysis-readonly-role`
2. `logs:DescribeLogGroups` → discovers `/prod/payment-service/application`
3. `logs:FilterLogEvents` (pattern: "password", "secret", "key") → finds creds
4. `logs:GetLogEvents` → reads full context around credential leaks
5. Attempts to use extracted credentials → triggers alerts

**AWS Services:** IAM, CloudWatch Logs

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/log-analysis-readonly-role | High |
| GetLogEvents | log-group:/prod/payment-service/application | Critical |
| FilterLogEvents | log-group:/prod/payment-service/application | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 16 — Encryption Key (KMS)

An attacker discovers a KMS key tagged `DataClassification=PII` with an alias `prod-customer-data-encryption`. They can describe the key and read its policy but decrypt is explicitly denied for everyone. Every decrypt attempt generates a critical detection signal.

**Attack Path:**
1. `sts:AssumeRole` → `kms-audit-readonly-role`
2. `kms:ListAliases` → discovers `alias/prod-customer-data-encryption`
3. `kms:DescribeKey` → sees key metadata (PII tag, rotation enabled)
4. `kms:GetKeyPolicy` → reads policy (sees who "should" have access)
5. `kms:Decrypt` → DENIED ⛔ (generates critical signal)

**AWS Services:** IAM, KMS

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/kms-audit-readonly-role | High |
| DescribeKey | key/<key-id> | High |
| Decrypt (DENIED) | key/<key-id> | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $1.00/mo (KMS Customer Managed Key)

---

### Scenario 17 — Fake SSO (Okta SAML)

An attacker discovers a SAML provider named `ProdOktaSSO` with metadata XML and two SAML-trusted roles (`AdministratorAccess` and `PowerUserAccess`). The roles cannot be assumed without a valid SAML assertion from a non-existent Okta org. Every failed assumption attempt is a critical signal.

**Attack Path:**
1. `sts:AssumeRole` → `sso-audit-readonly-role`
2. `iam:ListSAMLProviders` → discovers `ProdOktaSSO`
3. `iam:GetSAMLProvider` → downloads metadata XML (Okta org URL, cert)
4. `iam:ListRoles` + `GetRole` → finds admin + developer roles
5. `sts:AssumeRoleWithSAML` → DENIED (no valid assertion) ⚠️

**AWS Services:** IAM, SAML Provider

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/sso-audit-readonly-role | High |
| GetSAMLProvider | saml-provider/ProdOktaSSO | High |
| AssumeRoleWithSAML (DENIED) | role/prod-okta-admin-role | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 18 — Tag Breadcrumbs

Resources are tagged with ARNs and S3 URIs referencing other resources, creating a breadcrumb trail. The attacker enumerates tags and discovers references to secrets, encryption keys, pipelines, and internal service endpoints — most of which don't exist.

**Attack Path:**
1. `sts:AssumeRole` → `resource-inventory-readonly-role`
2. `tag:GetResources` → enumerates all tagged resources
3. Reads tags → discovers ARNs pointing to other resources
4. Follows breadcrumbs → probes referenced resources → generates signals

**AWS Services:** IAM, Resource Groups Tagging API, SSM

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/resource-inventory-readonly-role | High |
| Any access to referenced resources | Various (most don't exist) | High |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 19 — Enriched User PII

An attacker reads a Lambda function's configuration and discovers Clearbit and FullContact API keys plus a DynamoDB table name. The table contains enriched user profiles with company info, titles, LinkedIn URLs, and enrichment scores.

**Attack Path:**
1. `sts:AssumeRole` → `etl-ops-readonly-role`
2. `lambda:GetFunctionConfiguration` → extracts API keys + table name
3. Attempts to access DynamoDB table → DENIED (no perms on discovery role)
4. Attempts to use Clearbit/FullContact keys → triggers external detection

**AWS Services:** IAM, Lambda, DynamoDB

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/etl-ops-readonly-role | High |
| GetFunctionConfiguration | function:prod-user-data-enrichment | Critical |
| DescribeTable (if attempted) | table/prod-enriched-user-profiles | High |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 20 — SSM Parameter Cross-Reference Chain

Five SSM parameters under `/prod/db/*` cross-reference each other via `see_also` fields. The attacker follows the chain: primary → replica → backup-config → encryption-config → monitoring, extracting credentials at each hop.

**Attack Path:**
1. `sts:AssumeRole` → `infra-params-readonly-role`
2. `ssm:GetParametersByPath` /prod/db → discovers all 5 parameters
3. Reads each parameter → follows `see_also` references
4. Extracts: DB creds, replica endpoint, backup config, KMS key ARN, Datadog keys

**AWS Services:** IAM, SSM Parameter Store (×5)

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/infra-params-readonly-role | High |
| GetParameter (×5) | parameter/prod/db/* | High |
| GetParametersByPath | parameter/prod/db | High |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

### Scenario 21 — CloudFormation Stack Outputs

A CloudFormation stack exposes fake database passwords, API keys, Redis auth tokens, and admin URLs in its outputs — mimicking a common real-world misconfiguration. Any `DescribeStacks` call reveals all secrets in plaintext.

**Attack Path:**
1. `sts:AssumeRole` → `cfn-audit-readonly-role`
2. `cloudformation:ListStacks` → discovers stacks
3. `cloudformation:DescribeStacks` → reads outputs with plaintext secrets ⚠️
4. `cloudformation:ListExports` → sees cross-stack export names (network topology)
5. Attempts to use credentials against endpoints → triggers alerts

**AWS Services:** IAM, CloudFormation, SSM

**Detection Signals:**

| Event | Resource | Confidence |
|-------|----------|------------|
| AssumeRole | role/cfn-audit-readonly-role | High |
| DescribeStacks | stack/prod-core-infrastructure | Critical |

**Diagram:** *(insert Lucid diagram)*

**Cost:** $0.00/mo

---

## Cost Summary

| # | Scenario | Monthly Cost |
|---|----------|-------------|
| 1 | Terraform State Lure | $0.00 |
| 2 | Payment Credentials | $1.20 |
| 3 | Infrastructure Vault | $0.05 |
| 4 | SSH Key → EC2 Bastion | $0.64 |
| 5 | ECR Container Image | $0.01 |
| 6 | Lambda Blueprint | $0.00 |
| 7 | Lambda Code Injection | $0.00 |
| 8 | Lambda Role Chaining | $0.40 |
| 9 | Role Chain Loop | $0.00 |
| 11 | Customer Data | $0.00 |
| 13 | Payment Events DLQ | $0.00 |
| 14 | Critical Alerts | $0.00 |
| 15 | Leaked Logs | $0.00 |
| 16 | Encryption Key | $1.00 |
| 17 | Fake SSO | $0.00 |
| 18 | Tag Breadcrumbs | $0.00 |
| 19 | Enriched User PII | $0.00 |
| 20 | SSM Chain | $0.00 |
| 21 | Stack Outputs | $0.00 |
| | **Total** | **~$3.70/mo** |

---

## Monitoring

No additional CloudTrail cost if leveraging an already-established organization trail. EventBridge rules filter directly from existing trail events.

| Component | Description | Cost |
|-----------|-------------|------|
| CloudTrail | Management events (existing trail) | $0.00 |
| EventBridge | Detection rules matching lure role names | $0.00 |
| SNS | Alert notification delivery | $0.00 |
| **Total** | | **$0.00** |

---

## Deployment Order

```
# Independent scenarios (any order)
scenario-1   → Terraform State
scenario-2   → Payment Credentials
scenario-3   → Infrastructure Vault
scenario-9   → Role Chain Loop
scenario-11  → Customer Data
scenario-13  → Payment Events DLQ
scenario-14  → Critical Alerts
scenario-15  → Leaked Logs
scenario-16  → Encryption Key
scenario-17  → Fake SSO
scenario-18  → Tag Breadcrumbs
scenario-19  → Enriched User PII
scenario-20  → SSM Chain
scenario-21  → Stack Outputs

# Dependent scenarios (deploy in order)
scenario-4   → EC2 Bastion (first)
scenario-5   → ECR Image (chains to scenario-4)
scenario-6   → Lambda Blueprint (first)
scenario-7   → Code Injection (links to scenario-6)
scenario-8   → Role Chaining (links to scenario-6)
```
