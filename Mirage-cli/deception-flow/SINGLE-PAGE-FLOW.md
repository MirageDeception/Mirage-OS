# `mirage` CLI — Single-Page Architecture & Flow

> Binary name: **`mirage`** | Language: Go + Cobra | IaC: Terraform
> Hub/Spoke model — Hub = management + monitoring, Spoke = deception targets

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        mirage  (Go binary)                                   │
│                                                                              │
│  Global: --region | --profile | --yes | --dry-run | --json                   │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │
       ┌───────────────────────────┼────────────────────────────┐
       ▼                           ▼                             ▼
┌────────────────┐   ┌──────────────────────────┐   ┌────────────────────────┐
│   INIT PHASE   │   │      HUB ACCOUNT         │   │   SPOKE ACCOUNT(S)     │
│                │   │  (Management/Monitoring)  │   │  (Deception Targets)   │
│ • Auth         │   │                           │   │                        │
│ • Org detect   │   │  • IAM roles (hub-side)   │   │ • IAM roles (spoke)    │
│ • Hub/Spoke    │   │  • Monitoring arch        │   │ • Decoy scenarios      │
│   enrollment   │   │  • Resource catalogue DB  │   │ • Forwarding rules     │
│ • Config write │   │  • SCP/Org controls       │   │                        │
└────────────────┘   └──────────────────────────┘   └────────────────────────┘
```

---

## CLI Precedence Over Terraform Values

**Pattern: Config → CLI flag → Terraform variable**

```
┌─────────────────────────────────────────────────────────┐
│  RESOLUTION ORDER (highest wins)                        │
│                                                         │
│  1. CLI flag (--name-prefix, --region, etc.)            │
│  2. Config file (~/.mirage/config.yaml)                 │
│  3. Terraform .tfvars defaults (placeholders)           │
└─────────────────────────────────────────────────────────┘

HOW IT WORKS:
  • Terraform templates use variable placeholders:
      variable "bucket_name" { default = "__PLACEHOLDER__" }

  • At deploy time, the CLI:
      1. Reads config.yaml for user-defined resource names
      2. Applies any CLI flag overrides
      3. Generates a terraform.tfvars file with resolved values
      4. Runs terraform apply -var-file=resolved.tfvars

  • User never edits .tf files directly for naming
```

**Why this approach:**
- Terraform templates remain reusable/shareable (no hardcoded names)
- Users customize via config once, applied everywhere
- CLI flags give one-off overrides without touching config
- No sed/replace hacks — proper tfvars injection

---

## `mirage init` — Full Bootstrap Flow

```
$ mirage init
         │
         ▼
┌─────────────────────────────────────┐
│  WELCOME                            │
│  Technology: AWS / Azure / GCP / K8s│
│  (select: AWS)                      │
└────────────┬────────────────────────┘
             ▼
┌─────────────────────────────────────┐
│  AUTH                               │
│  • Login method: SSO / Access Keys  │
│  • aws sts get-caller-identity      │
│  • Display: Account=X, Principal=Y  │
└────────────┬────────────────────────┘
             ▼
┌─────────────────────────────────────┐
│  AWS ORGANIZATION CHECK             │
│  "Is this an Organization account?" │
│                                     │
│  YES ──────────────────┐            │
│  NO (Hub-only mode) ───┼──►        │
└────────────────────────┬┼───────────┘
                         ▼▼
         ┌───────────────────────────────────────────────┐
         │  IF ORG:                                      │
         │  • Deploy cross-account roles in Org account  │
         │  • Binary assumes this role for operations    │
         │  • "What are your spoke accounts?"            │
         │     1. Single spoke (dev or prod)             │
         │     2. Multi spoke (comma-separated list)     │
         │  • Input file path (default: prod)            │
         │  • Setup SCP & Org-wide controls              │
         │                                               │
         │  IF NON-ORG BUT HUB:                          │
         │  • Manually specify spoke account IDs         │
         │  • Skip Org-level SCP setup                   │
         └───────────────────────────┬───────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────┐
│  ROLE DEPLOYMENT                                        │
│  • "Deploy roles now, or set up later?"                  │
│     → NOW: run `mirage roles deploy --all-spokes`       │
│     → LATER: `mirage roles deploy` or `roles import`    │
│  • Display policies to be attached                      │
│  • Confirmation: Y/N                                    │
└────────────────────────────────────┬────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────┐
│  WRITE CONFIG → ~/.mirage/config.yaml                   │
│  • hub_account, spoke_accounts[], region, emails        │
│  • resource_naming (see naming section below)           │
│  • catalogue_backend: local_sqlite | dynamodb           │
└─────────────────────────────────────────────────────────┘
```

---

## Cross-Account Role Management

Roles are the prerequisite for everything. They can be deployed via `mirage init`
(bundled) OR managed independently via `mirage roles` (for teams where IAM is
owned by a separate platform/security team).

```
┌──────────────────────────────────────────────────────────────────────┐
│  "I'm setting up fresh — nobody has roles yet"                       │
│                                                                       │
│  $ mirage roles deploy --all-spokes                                  │
│    → Creates mirage-deployment-role in each spoke (hub assumes it)    │
│    → Creates mirage-forwarding-role in each spoke (events only)       │
│    → Updates hub bus policy to allow forwarding                       │
│    → Writes role ARNs to config                                       │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│  "Our platform team already created roles / we use Control Tower"     │
│                                                                       │
│  $ mirage roles import dev --role-arn arn:aws:iam::...:role/existing  │
│    → Validates role is assumable from hub (STS test)                  │
│    → Checks attached policies cover required actions                  │
│    → Writes ARN to config (no infra deployed)                         │
│    → If permissions insufficient → prints required policy JSON        │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│  "I need to give the spoke admin a template to deploy themselves"     │
│                                                                       │
│  $ mirage roles export-template --spoke dev --format terraform       │
│    → Generates a self-contained .tf file the spoke admin can apply    │
│    → Includes trust policy, permissions, boundary                     │
│    → Spoke admin runs: terraform apply                                │
│    → Then you run: mirage roles import dev --role-arn <output>        │
└──────────────────────────────────────────────────────────────────────┘

ROLE ARCHITECTURE:
┌─────────────────────────────┐          ┌────────────────────────────┐
│  HUB ACCOUNT                │          │  SPOKE ACCOUNT             │
│                             │ assumes  │                            │
│  mirage binary              │────────►│  mirage-deployment-role    │
│  (or CI pipeline)           │          │  • Trust: hub + ExternalId │
│                             │          │  • Perms: deception only   │
│                             │          │  • Boundary: no escalation │
│  Event Bus Policy           │◄────────│                            │
│  • Allow PutEvents from     │  events  │  mirage-forwarding-role    │
│    spoke forwarding role    │          │  • Trust: events.amazonaws │
│                             │          │  • Perms: PutEvents ONLY   │
└─────────────────────────────┘          └────────────────────────────┘
```

---

## Deception Scenario Deployment

```
$ mirage scenario deploy
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│  NAMING CONVENTION INPUT                                │
│                                                         │
│  "Resource naming pattern for spoke accounts?"          │
│  • List of patterns shown:                              │
│    Pattern: Placeholder-Scenario-___-___-___-___        │
│    [Dev also: Pattern Service(Bucket/Role/Parameter)]   │
│                                                         │
│  If config already has naming → use it                  │
│  If user overrides via flag → use flag                  │
│  Otherwise → prompt once, save to config                │
└────────────────────────────────────┬────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────┐
│  SELECT DECEPTION SCENARIO                              │
│                                                         │
│  Browse by:                                             │
│    1. Deployment by Service (S3, IAM, Lambda, etc.)     │
│    2. Deployment by Category (credential, data, pivot)  │
│                                                         │
│  Select: <n> or --all                                   │
└────────────────────────────────────┬────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────┐
│  DEPLOYMENT FLOW                                        │
│                                                         │
│  1. Fetch terraform template from:                      │
│     • Raw.github.com/<repo>/scenario-N/  (remote)       │
│     • OR local path ./mirage/scenario/   (bundled)      │
│                                                         │
│  2. Save locally in ~/.mirage/scenarios/scenario-N/     │
│                                                         │
│  3. Resolve placeholders from config naming conventions │
│     (generate terraform.tfvars with resolved names)     │
│                                                         │
│  4. terraform init → plan → apply                       │
│                                                         │
│  5. Seed fake-data (post-apply)                         │
│                                                         │
│  6. Catalogue deployed resources:                       │
│     • Account → Scenario → Resources → ARNs            │
│     • Store in local SQLite or DynamoDB                 │
│     • User chooses backend at init time                 │
└─────────────────────────────────────────────────────────┘
```

---

## Monitoring Architecture Deployment

```
$ mirage monitor deploy
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│  FETCH MONITORING TERRAFORM                             │
│  • From GitHub (raw) or local script                    │
│  • Save to ~/.mirage/monitoring/                        │
└────────────────────────────────────┬────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────┐
│  DEPLOY IN HUB ACCOUNT                                  │
│                                                         │
│  [1] Brain module:                                      │
│      EventBus + Lambda processor + SNS + IAM            │
│      → outputs: lambda_arn, sns_topic_arn, bus_arn      │
│                                                         │
│  [2] Detection rules module:                            │
│      19 EventBridge rules (one per scenario)            │
│      → reads resource catalogue for ARN matching        │
│                                                         │
│  [3] Subscribe alert emails                             │
│                                                         │
│  [4] Authorize spoke account(s) on event bus            │
└────────────────────────────────────┬────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────┐
│  DEPLOY FORWARDING IN SPOKE ACCOUNT(S)                  │
│                                                         │
│  • 2 EventBridge forwarding rules → Hub bus             │
│  • Forwarding IAM role                                  │
│  • Auto-reads catalogue for decoy ARNs to match on     │
└─────────────────────────────────────────────────────────┘
```

---

## Resource Naming & Config System

```yaml
# ~/.mirage/config.yaml

cloud: aws
region: us-west-2

accounts:
  hub: "<hub-account-id>"        # management + monitoring
  spokes:
    - id: "<spoke-1>"
      alias: "dev"
    - id: "<spoke-2>"
      alias: "prod"

alerts:
  emails:
    - team-lead@company.com
    - soc@company.com

# --- NAMING CONVENTIONS (the key piece) ---
naming:
  prefix: "corp"                           # e.g., corp-terraform-state-bucket
  separator: "-"
  patterns:
    s3_bucket: "{prefix}-{scenario_slug}-{suffix}"
    iam_role: "{prefix}-{scenario_slug}-role"
    lambda: "{prefix}-{scenario_slug}-fn"
    ssm_parameter: "/{prefix}/{scenario_slug}/{key}"
    dynamodb_table: "{prefix}-{scenario_slug}-table"
    sqs_queue: "{prefix}-{scenario_slug}-queue"
    sns_topic: "{prefix}-{scenario_slug}-topic"
    kms_key_alias: "alias/{prefix}-{scenario_slug}"
  # User can override individual scenario names:
  overrides:
    scenario-1:
      s3_bucket: "infra-terraform-state-prod-backup"
    scenario-4:
      iam_role: "bastion-ssh-readonly-access"

catalogue:
  backend: sqlite              # sqlite | dynamodb
  # if dynamodb:
  # table_name: mirage-resource-catalogue
  # region: us-west-2
```

**How naming flows into Terraform:**

```
config.yaml (naming.patterns)
       │
       ▼
CLI resolves patterns → generates scenario-N.tfvars
       │
       ▼
terraform apply -var-file=scenario-N.tfvars
       │
       ▼
Resources created with user-defined names
       │
       ▼
ARNs written to catalogue DB
       │
       ▼
Monitoring rules auto-reference catalogue ARNs
```

---

## Resource Catalogue (State of Truth)

```
┌──────────────────────────────────────────────────────────┐
│  CATALOGUE (SQLite local or DynamoDB)                    │
│                                                          │
│  account_id | scenario | resource_type | name | arn      │
│  ───────────┼──────────┼──────────────┼──────┼────────  │
│  <spoke-1>  | 1        | s3_bucket    | ...  | arn:...  │
│  <spoke-1>  | 1        | iam_role     | ...  | arn:...  │
│  <spoke-1>  | 2        | secret       | ...  | arn:...  │
│  <spoke-2>  | 1        | s3_bucket    | ...  | arn:...  │
│                                                          │
│  USED BY:                                                │
│  • Monitoring rules (to know which ARNs to alert on)    │
│  • Status command (reconcile deployed vs expected)       │
│  • Destroy command (knows exactly what to tear down)     │
│  • Verify command (picks a decoy ARN to test)           │
└──────────────────────────────────────────────────────────┘
```

---

## Complete Command Surface

```
mirage
├── init                         bootstrap (auth, org, hub/spoke, config)
├── roles
│   ├── deploy [--spoke|--all-spokes|--hub]  create cross-account IAM roles
│   ├── destroy [--spoke|--all-spokes]       remove roles (breaks operations)
│   ├── import <alias> --role-arn <arn>      use pre-existing roles (skip deploy)
│   ├── status                               validate roles are assumable + healthy
│   └── export-template                      generate TF/CFN for spoke admin to deploy
├── scenario
│   ├── list [--service|--category]   browse available scenarios
│   ├── show <n>                      scenario details + resources
│   ├── deploy <n|--all>              fetch template → resolve names → apply
│   ├── destroy <n|--all>             tear down + remove from catalogue
│   ├── abuse <n>                     ⚠️ explicit attacker sim (no --all)
│   └── status [<n>]                  per-scenario health
├── monitor
│   ├── deploy                        brain + rules (hub account)
│   ├── forwarding                    spoke-side event forwarding
│   ├── authorize <spoke-id>          grant spoke → hub bus access
│   ├── subscribe <email>             add alert recipient
│   ├── status                        monitoring health
│   └── destroy                       tear down monitoring
├── status                            end-to-end matrix (all planes)
├── verify [--scenario <n>]           safe synthetic drill
├── catalogue
│   ├── show                          list all tracked resources
│   ├── sync                          reconcile catalogue ↔ live state
│   └── export [--json|--csv]         dump for audit
└── config
    ├── show                          print current config
    └── set <key> <value>             update config value
```

---

## Deploy Order (enforced by CLI)

```
┌─────────────────────────────────────────────────────────┐
│  ① mirage init                                          │
│     → Auth, detect org, enroll hub + spokes             │
│     → Write config + naming conventions                 │
│                                                         │
│  ② mirage roles deploy (OR roles import)                │
│     → Cross-account IAM roles in each spoke             │
│     → Hub bus policy updated                            │
│     → Skip if roles already exist (use `roles import`)  │
│                                                         │
│  ③ mirage monitor deploy          (Hub account)         │
│     → Brain (EventBus, Lambda, SNS)                     │
│     → Detection rules                                   │
│     → Authorize spoke(s)                                │
│                                                         │
│  ④ mirage monitor forwarding      (Each spoke)          │
│     → Forwarding rules + IAM role → Hub bus             │
│                                                         │
│  ⑤ mirage scenario deploy <n>     (Each spoke)          │
│     → Fetch template → resolve naming → apply           │
│     → Seed fake data                                    │
│     → Register in catalogue                             │
└─────────────────────────────────────────────────────────┘
```

---

## Scalability Design (Hub-Spoke Fan-Out)

```
                    ┌──────────────┐
                    │   HUB ACCT   │
                    │  (Monitor +  │
                    │   Manage)    │
                    └──────┬───────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
     ┌────────────┐ ┌────────────┐ ┌────────────┐
     │  SPOKE A   │ │  SPOKE B   │ │  SPOKE N   │
     │  (dev)     │ │  (staging) │ │  (prod)    │
     │  decoys    │ │  decoys    │ │  decoys    │
     │  fwd rules │ │  fwd rules │ │  fwd rules │
     └────────────┘ └────────────┘ └────────────┘

• Each spoke independently forwards to Hub event bus
• Hub detection rules reference catalogue (all spokes' ARNs)
• Adding a spoke = `mirage init --add-spoke <id>` + deploy forwarding + scenarios
• Removing a spoke = `mirage scenario destroy --all` + remove from config
```

---

## Internal Package Structure

```
mirage/
├── cmd/mirage/main.go              ← entry point
└── internal/
    ├── cmd/                        ← Cobra commands (thin handlers)
    │   ├── root.go                 ← global flags
    │   ├── init.go                 ← bootstrap wizard
    │   ├── roles.go                ← deploy/destroy/import/status/export-template
    │   ├── scenario.go             ← list/show/deploy/destroy/abuse
    │   ├── monitor.go              ← deploy/forwarding/authorize
    │   ├── status.go               ← reconciled end-to-end view
    │   ├── verify.go               ← synthetic drill
    │   ├── catalogue.go            ← show/sync/export
    │   └── config.go               ← show/set
    ├── awsctx/                     ← sts identity, role classification
    ├── config/                     ← config.yaml + naming resolution
    ├── roles/                      ← cross-account IAM role lifecycle
    │   ├── deploy.go               ← create roles in spokes (StackSets or TF)
    │   ├── import.go               ← validate + register pre-existing roles
    │   ├── destroy.go              ← remove roles + revoke bus policy
    │   ├── status.go               ← health check (assumable? perms ok?)
    │   └── template.go             ← generate exportable TF/CFN for spoke admins
    ├── discovery/                  ← walk scenarios, match event rules
    ├── naming/                     ← pattern resolution engine
    │   └── resolver.go             ← "{prefix}-{slug}" → real name
    ├── tf/                         ← terraform init/plan/apply wrapper
    │   └── tfvars.go               ← generate .tfvars from resolved names
    ├── catalogue/                  ← SQLite/DynamoDB resource registry
    ├── monitor/                    ← brain+rules+forwarding orchestration
    ├── templates/                  ← fetch from GitHub or local cache
    └── verify/                     ← synthetic alert + round-trip check
```

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Config > Terraform defaults | Users define naming once; CLI injects via tfvars. No manual .tf edits. |
| Catalogue DB (SQLite/DynamoDB) | Track what's deployed where — enables multi-spoke status + dynamic rule generation. |
| Fetch templates from GitHub | Scenarios stay in a central repo; CLI pulls what it needs. No local bloat. |
| Hub-Spoke over flat accounts | Natural Org boundary; monitoring centralised; spokes are disposable. |
| Naming patterns with overrides | Sane defaults + full customisation per scenario without forking templates. |
| Account-role guard on every cmd | Prevents the #1 mistake (deploying in wrong account) with zero user effort. |
| Placeholder tfvars (not sed) | Clean, Terraform-native; `terraform plan` still works standalone for debugging. |
