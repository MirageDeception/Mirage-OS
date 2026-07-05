# Session 3 — Build IaC for Scenarios 18, 19, 20, 21

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

### Scenario 18 — Resource Tags Breadcrumb Trail
- Read `scenarios/scenario-18/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`
- Minimal resources (IAM role + SSM parameter) with tags that reference other resources
- Tags contain S3 bucket ARNs, secret ARNs, role ARNs as breadcrumbs (referenced resources don't need to exist)
- Abuse script: assume role, use tag:GetResources / resourcegroupstaggingapi, follow breadcrumbs

### Scenario 19 — Lambda + DynamoDB Enriched User PII
- Read `scenarios/scenario-19/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, `fake-data/enriched-users.json`
- Lambda function `prod-user-data-enrichment` with env vars (DynamoDB table name, Clearbit/FullContact API keys)
- Lambda execution role with DynamoDB read/write scoped to the lure table
- DynamoDB PAY_PER_REQUEST table `prod-enriched-user-profiles`, partition key `user_id`, sort key `email`
- Deploy script seeds 10-15 enriched user records (name, company, job title, linkedin, enrichment score, revenue estimate, tech stack)
- Abuse script: assume role, list functions, get config, scan DynamoDB table

### Scenario 20 — SSM Parameter Cross-Reference Chain
- Read `scenarios/scenario-20/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`, `fake-data/` with 5 JSON files
- 5 SSM parameters under `/prod/db/*` that cross-reference each other via `see_also` field
- Chain: primary → replica → backup-config → encryption-config → monitoring
- Each parameter has credentials AND a pointer to the next
- Abuse script: assume role, describe parameters, follow the chain reading each one

### Scenario 21 — CloudFormation Stack Outputs with Exposed Secrets
- Read `scenarios/scenario-21/PROMPT.md` for full spec
- Create: `template.yaml`, `deploy.sh`, `README.md`, `abuse.sh`
- Stack creates minimal resources (SSM parameters as placeholders) but exposes secrets in stack OUTPUTS
- Outputs: DatabaseEndpoint, DatabasePassword, ApiGatewayUrl, ApiKey, RedisEndpoint, RedisAuthToken, AdminDashboardUrl
- Stack exports with enticing cross-stack reference names (prod-vpc-id, prod-private-subnet-ids, etc.)
- Abuse script: assume role, list stacks, describe stacks (read outputs), list exports

## Style Reference

Look at `scenarios/scenario-6/template.yaml`, `scenarios/scenario-6/deploy.sh`, and
`scenarios/scenario-1/abuse.sh` for the established patterns.
