# Scenario 20 — SSM Parameter Cross-Reference Chain

## Prompt

Create a deception scenario called `scenario-20` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: infra-params-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► ssm:DescribeParameters → finds /prod/db/* hierarchy
  │
  ├─► Reads /prod/db/primary → contains connection string + reference to /prod/db/replica
  │
  ├─► Reads /prod/db/replica → contains replica endpoint + reference to /prod/db/backup-config
  │
  ├─► Reads /prod/db/backup-config → contains S3 backup bucket + encryption key ref
  │
  ├─► Reads /prod/db/encryption-config → contains KMS key ARN + key rotation schedule
  │
  ├─► Reads /prod/db/monitoring → contains Datadog integration + alert webhook
  │
  └─► Each parameter is a breadcrumb to the next → generates 5+ CloudTrail events
```

### Lure Resources

- **IAM Role**: Named `infra-params-readonly-role`
  - `ssm:DescribeParameters`
  - `ssm:GetParameter`, `ssm:GetParameters` — scoped to `/prod/db/*`
  - `ssm:GetParametersByPath` — scoped to `/prod/db` and `/prod/db/*`
  - Trust: account root principal

- **SSM Parameters** (all Standard tier, $0.00):

  1. `/prod/db/primary` — Primary DB connection with `"see_also": "/prod/db/replica"`
  2. `/prod/db/replica` — Replica endpoint with `"see_also": "/prod/db/backup-config"`
  3. `/prod/db/backup-config` — Backup S3 bucket + schedule with `"see_also": "/prod/db/encryption-config"`
  4. `/prod/db/encryption-config` — KMS key ARN + rotation with `"see_also": "/prod/db/monitoring"`
  5. `/prod/db/monitoring` — Datadog/PagerDuty integration keys + webhook URLs

### Fake Data to Seed

Each parameter value is JSON containing credentials AND a `see_also` field pointing
to the next parameter — creating a breadcrumb chain the attacker follows.

### Additional Requirements

- [ ] Cost: $0.00/month (SSM Standard = free)
- [ ] Each parameter cross-references the next, creating a trail
- [ ] Include `deploy.sh`, `README.md`, `fake-data/` with JSON for each parameter
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-20/
├── template.yaml
├── deploy.sh
├── fake-data/
│   ├── db-primary.json
│   ├── db-replica.json
│   ├── db-backup-config.json
│   ├── db-encryption-config.json
│   └── db-monitoring.json
└── README.md
```
