# Data Model

Four structures: **config** (intent), **naming system** (identity blending),
**catalogue** (deployed state), and **scenario manifest** (template metadata).

---

## 1. Config — `~/.mirage/config.yaml`

The config stores operator intent. No secrets, no ARNs — those are derived at
runtime. No hardcoded account IDs in code; everything is config-driven.

```yaml
# ~/.mirage/config.yaml

version: "1"                       # config schema version (for migrations)

cloud: aws                          # aws | azure | gcp | k8s (future)
region: us-west-2

# --- ACCOUNT TOPOLOGY ---
accounts:
  hub:
    id: ""                          # filled at init time
    alias: "security-hub"
    org_managed: true               # true = Org account, false = standalone
  spokes:
    - id: ""
      alias: "dev"
      environment: "development"
    - id: ""
      alias: "staging"
      environment: "staging"
    - id: ""
      alias: "prod"
      environment: "production"

# --- ALERTING ---
alerts:
  emails: []                        # filled at init time
  # future: slack_webhook, pagerduty, etc.

# --- NAMING CONVENTIONS ---
naming:
  prefix: "corp"
  separator: "-"
  patterns:
    s3_bucket: "{prefix}-{scenario_slug}-{suffix}"
    iam_role: "{prefix}-{scenario_slug}-role"
    lambda_function: "{prefix}-{scenario_slug}-fn"
    ssm_parameter: "/{prefix}/{scenario_slug}/{key}"
    dynamodb_table: "{prefix}-{scenario_slug}-table"
    sqs_queue: "{prefix}-{scenario_slug}-queue"
    sns_topic: "{prefix}-{scenario_slug}-topic"
    kms_key_alias: "alias/{prefix}-{scenario_slug}"
    secrets_manager: "{prefix}/{scenario_slug}/{key}"
    ecr_repository: "{prefix}-{scenario_slug}"
    cloudwatch_log_group: "/aws/{prefix}/{scenario_slug}"

  # Per-scenario overrides (for maximum realism)
  overrides:
    scenario-1:
      s3_bucket: "infra-terraform-state-prod-backup"
      iam_role: "infra-s3-data-readonly-role"
    scenario-4:
      iam_role: "bastion-ssh-readonly-access"
    # ... operators define these to match their real naming style

# --- CATALOGUE ---
catalogue:
  backend: sqlite                   # sqlite | dynamodb
  sqlite_path: "~/.mirage/catalogue.db"
  # dynamodb:
  #   table_name: "mirage-resource-catalogue"
  #   region: "us-west-2"

# --- TEMPLATE SOURCE ---
templates:
  source: github                    # github | local | s3
  github:
    repo: "org/cloud-deception-scenarios"
    branch: "main"
    path: "scenarios/"
  # local:
  #   path: "./scenarios"
  # s3:
  #   bucket: "deception-templates"
  #   prefix: "scenarios/"

# --- MONITORING ---
monitoring:
  event_bus_name: "deception-global-event-bus"
  lambda_runtime: "python3.11"
  alert_severity_levels:
    - CRITICAL    # resource-specific data access
    - HIGH        # AssumeRole on lure roles

# --- OPERATIONAL ---
operational:
  auto_verify_after_deploy: false   # run verify after each scenario deploy
  verify_timeout_seconds: 30
  max_parallel_deploys: 5           # for --all with many scenarios
```

**Security notes:**
- No account IDs stored in version control — `config.yaml` is local to the
  operator's machine (or encrypted in team vault).
- `naming.overrides` is where deception blending happens — operators study their
  real resource names and mimic them exactly.
- The config schema has a `version` field so future migrations are non-breaking.

---

## 2. Naming System (Resolution Engine)

The naming system is the core mechanism for deception blending. It resolves
template placeholders into realistic resource names.

### Resolution Order (highest precedence wins)

```
┌─────────────────────────────────────────────┐
│  1. CLI flag:      --name-prefix "prod"     │  ← one-off override
│  2. Config override: naming.overrides.N     │  ← per-scenario custom
│  3. Config pattern: naming.patterns.*       │  ← templated defaults
│  4. Terraform default: "__PLACEHOLDER__"    │  ← never reaches AWS
└─────────────────────────────────────────────┘
```

### Pattern Variables

| Variable | Source | Example |
|----------|--------|---------|
| `{prefix}` | `naming.prefix` in config | `corp` |
| `{scenario_slug}` | derived from scenario name | `terraform-state`, `payment-creds` |
| `{suffix}` | random or account-derived | `a3f9`, account-id last 4 |
| `{key}` | resource-specific (SSM path, secret name) | `db-password` |
| `{region}` | config.region | `us-west-2` |
| `{account_id}` | runtime STS identity | `123456789012` |
| `{spoke_alias}` | config.accounts.spokes[].alias | `dev` |

### Example Resolution

```
Config:
  naming.prefix = "corp"
  naming.patterns.s3_bucket = "{prefix}-{scenario_slug}-{suffix}"
  naming.overrides.scenario-1.s3_bucket = "infra-terraform-state-prod-backup"

Scenario 1 (has override):
  → bucket_name = "infra-terraform-state-prod-backup"  (exact override)

Scenario 2 (no override, uses pattern):
  → bucket_name = "corp-payment-creds-a3f9"  (pattern-resolved)
```

### How It Flows Into Terraform

```
resolver.Resolve(scenario=2, resourceType="s3_bucket")
  │
  ▼
Check overrides → miss
Check patterns  → hit: "{prefix}-{scenario_slug}-{suffix}"
Interpolate     → "corp-payment-creds-a3f9"
  │
  ▼
Write to scenario-2.tfvars:
  bucket_name = "corp-payment-creds-a3f9"
  │
  ▼
terraform apply -var-file=scenario-2.tfvars
  (template has: variable "bucket_name" { default = "__PLACEHOLDER__" })
```

---

## 3. Catalogue Schema (Deployed State)

The catalogue tracks what exists in AWS. It's the security posture record.

### SQLite Schema

```sql
CREATE TABLE resources (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id      TEXT NOT NULL,
    spoke_alias     TEXT NOT NULL,
    scenario_num    INTEGER NOT NULL,
    scenario_name   TEXT NOT NULL,
    resource_type   TEXT NOT NULL,    -- s3_bucket, iam_role, lambda, etc.
    resource_name   TEXT NOT NULL,    -- the resolved name
    arn             TEXT,             -- populated after terraform apply
    deployed_at     DATETIME NOT NULL,
    destroyed_at    DATETIME,         -- NULL if still live
    last_verified   DATETIME,         -- last successful verify
    deployed_by     TEXT NOT NULL,    -- operator principal (from STS)
    tf_state_path   TEXT,            -- path to terraform state file
    status          TEXT DEFAULT 'active'  -- active | destroyed | orphaned | unknown
);

CREATE TABLE operations_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp       DATETIME NOT NULL,
    operator        TEXT NOT NULL,    -- STS principal
    command         TEXT NOT NULL,    -- e.g., "scenario deploy 3"
    account_id      TEXT NOT NULL,
    spoke_alias     TEXT,
    scenario_num    INTEGER,
    action          TEXT NOT NULL,    -- deploy | destroy | abuse | verify
    result          TEXT NOT NULL,    -- success | failure | dry-run
    details         TEXT             -- JSON blob with extra context
);

CREATE TABLE spokes (
    account_id      TEXT PRIMARY KEY,
    alias           TEXT NOT NULL,
    environment     TEXT,
    enrolled_at     DATETIME NOT NULL,
    forwarding_deployed BOOLEAN DEFAULT FALSE,
    authorized_on_bus   BOOLEAN DEFAULT FALSE,
    last_status_check   DATETIME
);

-- Indices for common queries
CREATE INDEX idx_resources_spoke ON resources(spoke_alias, status);
CREATE INDEX idx_resources_scenario ON resources(scenario_num, status);
CREATE INDEX idx_operations_time ON operations_log(timestamp DESC);
```

### DynamoDB Schema (team/shared mode)

```
Table: mirage-resource-catalogue
  PK: SPOKE#<alias>#SCENARIO#<n>
  SK: RESOURCE#<type>#<name>
  Attributes: arn, deployed_at, deployed_by, last_verified, status

Table: mirage-operations-log
  PK: DATE#<yyyy-mm-dd>
  SK: TS#<iso-timestamp>#<operator>
  Attributes: command, account_id, scenario_num, action, result, details
```

### Catalogue Operations

| Operation | When | What it does |
|-----------|------|--------------|
| Register | after `scenario deploy` | Insert new resource entries with ARNs |
| Deregister | after `scenario destroy` | Mark `destroyed_at`, status = destroyed |
| Sync | `catalogue sync` | Compare catalogue vs `terraform state` + live AWS; flag drift |
| Verify update | after `verify` | Update `last_verified` timestamp |
| Audit log | every mutating command | Insert into operations_log |

---

## 4. Scenario Manifest (Template Metadata)

Each scenario template includes a manifest file (`scenario.yaml`) that the CLI
reads for discovery and resolution.

```yaml
# scenarios/scenario-1/scenario.yaml

number: 1
name: "Lure Terraform State Bucket"
slug: "terraform-state"                 # used in naming patterns
version: "1.2.0"

category: "credential-theft"            # credential-theft | data-exfil | lateral-movement | privilege-escalation
service: "s3"                           # primary AWS service

description: |
  Deploys a realistic S3 bucket mimicking a Terraform state file backend.
  Includes a lure IAM role that grants read access. Any AssumeRole or
  GetObject triggers an alert.

resources:
  - type: iam_role
    tf_variable: "role_name"            # the terraform variable to inject
    purpose: "lure role for S3 access"
  - type: s3_bucket
    tf_variable: "bucket_name"
    purpose: "fake terraform state bucket"

seed:
  - kind: s3
    source: "fake-data/terraform.tfstate"
    destination_key: "env/production/terraform.tfstate"

attack_path:
  - "Attacker discovers role ARN (e.g., from metadata, config leak)"
  - "Attacker calls sts:AssumeRole on the lure role"
  - "Attacker calls s3:GetObject on the state file"
  - "Both actions trigger detection"

detection:
  events:
    - source: "aws.sts"
      detail_type: "AWS API Call via CloudTrail"
      api_calls: ["AssumeRole"]
    - source: "aws.s3"
      detail_type: "AWS API Call via CloudTrail"
      api_calls: ["GetObject", "ListObjects"]
  severity: "CRITICAL"

terraform:
  required_variables:
    - "bucket_name"
    - "role_name"
    - "account_id"
    - "region"
  outputs:
    - "bucket_arn"
    - "role_arn"
```

### Discovery Logic

```
discoverScenarios(source):
  for each scenario dir in source:
    manifest = read scenario.yaml
    if manifest missing → infer from main.tf variables + README title
    if manifest.resources empty → skip (placeholder folder)
    yield Scenario{
      number, name, slug, category, service,
      resources, seed, detection, terraform
    }
```

### Template Repository Layout

```
scenarios/
├── scenario-1/
│   ├── scenario.yaml        ← manifest (metadata + discovery)
│   ├── main.tf              ← terraform resources
│   ├── variables.tf         ← all names are variables (no hardcoded)
│   ├── outputs.tf           ← resource ARNs for catalogue
│   ├── fake-data/           ← seeded post-apply
│   │   └── terraform.tfstate
│   └── README.md            ← human-readable story
├── scenario-2/
│   ├── scenario.yaml
│   ├── main.tf
│   └── ...
└── manifest.json            ← hash manifest for integrity verification
    {
      "scenario-1": { "sha256": "abc123...", "version": "1.2.0" },
      "scenario-2": { "sha256": "def456...", "version": "1.0.0" }
    }
```

---

## 5. Reality Checks (Runtime Queries — Never Stored)

| Question | How the CLI answers it |
|----------|------------------------|
| Is decoy N deployed? | `terraform state list` in scenario-N state → resources present |
| Is forwarding live? | `aws events list-rules` in spoke → forwarding rules ENABLED |
| Is the brain live? | `terraform state list` in hub/brain state → resources present |
| Is this spoke authorised? | `aws events describe-event-bus` → policy includes spoke account |
| Are emails confirmed? | `aws sns list-subscriptions-by-topic` → Confirmed vs Pending |
| Does an alert fire? | `mirage verify` → round-trip test |
| Is catalogue in sync? | `mirage catalogue sync` → compare DB vs terraform state vs live AWS |

**Golden rule:** Config = intent. Catalogue = expected state. Live AWS = reality.
`status` reconciles all three.
