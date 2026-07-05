# Session 2 — Build IaC for Scenarios 14, 15, 16, 17

## Context

You are building AWS CloudFormation deception scenarios. Each scenario is an internal-only
honeypot designed to detect insider threats or attackers already inside the AWS account.

## Rules (apply to ALL scenarios)

- **NO public access** — all resources are internal account-only decoys
- **Least privilege** — each role only gets the exact permissions needed for the scenario
- **NO cross-account** — no external account references
- **NO IAM users** — only IAM roles
- **NO FAKE/EXPIRED/REVOKED/REDACTED** labels in any data — everything must look legitimate
- Trust policies use `arn:aws:iam::<AccountId>:root` for discovery roles
- S3 buckets: full PublicAccessBlock, AES256 encryption, versioning, TLS-only
- Secrets Manager: resource policy allows read from account root only
- SSM: Standard tier
- Default region: `us-west-2`
- Deploy scripts: `set -euo pipefail`, colored output (CYAN for info, GREEN for ok, YELLOW for warn), comments
- Each scenario gets: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, and `fake-data/` if needed

## Scenarios to Build

### Scenario 14 — SNS Critical Alerts Topic
- Read `scenarios/scenario-14/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`
- SNS topic with SSE encryption, topic policy allows publish from account root only
- Subscriptions: HTTPS endpoint + email (both stay PendingConfirmation — no real delivery)
- Abuse script: assume role, list topics, get attributes, list subscriptions

### Scenario 15 — CloudWatch Logs with Leaked Credentials
- Read `scenarios/scenario-15/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, `fake-data/log-entries.json`
- CloudWatch Log Group with 30-day retention
- Deploy script seeds 10-15 log entries via `aws logs put-log-events` across 2-3 streams
- Mix normal logs with credential-leaking ones (DB connection strings in stack traces, API keys in debug headers, passwords in auth failures, env var dumps)
- Abuse script: assume role, describe log groups, describe streams, get log events, filter for keywords

### Scenario 16 — KMS Key (Describe-Only, Deny Decrypt)
- Read `scenarios/scenario-16/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`
- KMS customer-managed symmetric key with alias `alias/prod-customer-data-encryption`
- Key policy: allow describe/list from account, explicitly deny decrypt from the lure role
- Lure role: kms:ListAliases, kms:DescribeKey, kms:ListGrants, kms:GetKeyPolicy — scoped to the key
- Abuse script: assume role, list aliases, describe key, list grants, attempt decrypt (expect denied)

### Scenario 17 — SAML Provider (Fake Okta SSO)
- Read `scenarios/scenario-17/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, `fake-data/saml-metadata.xml`
- Deploy script generates a self-signed certificate and builds SAML metadata XML
- SAML provider `ProdOktaSSO` with realistic metadata
- Two SAML-trusted roles (admin + developer) that can't be assumed without valid SAML assertion
- Abuse script: assume discovery role, list SAML providers, get provider metadata, list roles, attempt assume (expect denied)

## Style Reference

Look at `scenarios/scenario-6/template.yaml`, `scenarios/scenario-6/deploy.sh`, and
`scenarios/scenario-1/abuse.sh` for the established patterns.
