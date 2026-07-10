# Command Tree & Flows

Full command surface for `mirage`. Each command lists args, flags, flow, and
security gates.

---

## Global Flags

| Flag | Default | Meaning |
|------|---------|---------|
| `--region` | `us-west-2` | AWS region for this operation. All regions supported; default is `us-west-2`. |
| `--profile` | (env) | AWS CLI named profile. |
| `--yes, -y` | false | Skip confirmation prompts (still logs). |
| `--dry-run` | false | Resolve + show terraform plan; don't apply. |
| `--json` | false | Machine-readable output for CI pipelines. |
| `--verbose` | false | Debug-level logging (includes AWS API calls). |

---

## `mirage init`

Bootstrap: authenticate, detect org structure, enroll hub + spokes, deploy
cross-account roles, set naming conventions, write config.

```
$ mirage init
 │
 ├─ Welcome banner + cloud provider selection (AWS / Azure / GCP / K8s)
 │
 ├─ AUTH
 │   ├─ Login method: SSO / Access Keys / Environment
 │   ├─ aws sts get-caller-identity → account + principal
 │   └─ Display: "Logged in as {principal} in account {account}"
 │
 ├─ ORGANIZATION CHECK
 │   ├─ aws organizations describe-organization (try; fail = non-org)
 │   ├─ IF ORG:
 │   │   ├─ Deploy management roles in org account
 │   │   ├─ Binary will assume this role for cross-account ops
 │   │   ├─ "What are your spoke accounts?"
 │   │   │    1. Single spoke — dev or prod
 │   │   │    2. Multi spoke — comma-separated list
 │   │   ├─ Input file path for account list (optional)
 │   │   └─ Setup SCP & Org-wide controls (optional)
 │   │
 │   └─ IF NON-ORG (Hub-only mode):
 │       ├─ Manually input spoke account IDs
 │       └─ Skip Org-level SCP setup
 │
 ├─ ROLE DEPLOYMENT
 │   ├─ Deploy IAM roles in each spoke account
 │   │   (cross-account assume role for terraform operations)
 │   ├─ Display policies to be attached
 │   ├─ Confirmation: Y/N
 │   └─ Deploy hub-side IAM role for spoke event forwarding
 │
 ├─ NAMING CONVENTIONS
 │   ├─ "Resource naming pattern for decoys?"
 │   ├─ Show pattern templates: {prefix}-{scenario_slug}-{suffix}
 │   ├─ Prompt for prefix (e.g., "corp", "infra", "prod")
 │   └─ Option to provide per-scenario overrides later via config
 │
 ├─ CATALOGUE BACKEND
 │   ├─ "Where to store resource catalogue?"
 │   │    1. Local SQLite (single operator, air-gapped)
 │   │    2. DynamoDB (team, shared state)
 │   └─ If DynamoDB → create table in hub account
 │
 └─ WRITE CONFIG → ~/.mirage/config.yaml
```

**Flags (non-interactive mode):**
`--hub <account-id>`, `--spoke <id>` (repeatable), `--email <e>` (repeatable),
`--prefix <name>`, `--catalogue sqlite|dynamodb`, `--org` / `--no-org`.

**Security gate:** None (init is always allowed — it's bootstrap).

---

## `mirage roles ...` (Cross-Account IAM Role Management)

Standalone command group for deploying, validating, and tearing down the
cross-account IAM roles that `mirage` needs to operate. Separated from `init`
because:

1. **Already deployed?** — If your org already has cross-account roles (e.g.,
   from a landing zone, Control Tower, or a prior `mirage init`), you can skip
   role deployment entirely and just point config at existing role ARNs.
2. **Different team owns IAM?** — In many orgs, the security/platform team
   creates roles and the deception team consumes them. `mirage roles` lets the
   IAM team run this independently.
3. **Rotate / update without re-init** — Policies evolve. You shouldn't need to
   re-bootstrap the whole tool to tighten a permission boundary.

### `roles status`

```
roles status
 ├─ For each spoke in config:
 │   ├─ attempt sts:AssumeRole on the expected cross-account role
 │   ├─ report: assumable? policy attached? last-used?
 │   └─ flag: MISSING | HEALTHY | STALE (not used in 90+ days)
 ├─ Hub-side role (spoke→hub event forwarding):
 │   └─ check bus policy includes spoke principals
 └─ Output matrix:
     spoke | role_arn | assumable | policy_ok | last_used
```

### `roles deploy [--spoke <alias> | --all-spokes | --hub]`

```
roles deploy
 ├─ GUARD: must be in hub account (roles are deployed FROM hub INTO spokes
 │         via Org or via cross-account CFN/TF)
 │
 ├─ IF ORG-MANAGED:
 │   ├─ use CloudFormation StackSets or Terraform with provider aliases
 │   │   to create roles in each spoke
 │   ├─ Role: mirage-deployment-role (hub assumes into spoke for TF ops)
 │   ├─ Trust policy: hub account only + ExternalId condition
 │   ├─ Permission boundary: scoped to deception resource types only
 │   └─ Role: mirage-forwarding-role (spoke → hub bus, PutEvents only)
 │
 ├─ IF NON-ORG (Hub-only mode):
 │   ├─ generate a CloudFormation/Terraform template for the spoke admin
 │   │   to deploy manually
 │   ├─ OR: if spoke creds available via --profile, deploy directly
 │   └─ print: "Share this template with the spoke account admin"
 │
 ├─ Hub-side: create/update the bus policy to allow spoke forwarding role
 │
 └─ Update config: roles.spoke_role_arn, roles.forwarding_role_arn per spoke
```

**Flags:** `--spoke <alias>` (target one spoke), `--all-spokes`, `--hub`
(hub-side bus policy only), `--export-template` (generate template without
deploying), `--dry-run`.

### `roles destroy [--spoke <alias> | --all-spokes]`

```
roles destroy
 ├─ WARN: "Destroying roles will break all mirage operations for this spoke"
 ├─ confirm (double-confirm: "Type spoke alias to confirm")
 ├─ remove role from spoke (StackSets delete or direct TF destroy)
 ├─ revoke bus policy entry for this spoke
 └─ update config: remove role ARNs for spoke
```

### `roles import <spoke-alias> --role-arn <arn> [--forwarding-role-arn <arn>]`

For when roles **already exist** (pre-provisioned by platform team, Control
Tower, or a previous tool):

```
roles import
 ├─ validate: attempt sts:AssumeRole on provided ARN
 │   ├─ SUCCESS → "Role is assumable from hub. ✓"
 │   └─ FAIL → "Cannot assume this role. Check trust policy."
 │             "Required: Principal=hub-account, Condition=ExternalId"
 ├─ validate: check attached policies cover required actions
 │   ├─ OK → "Permissions sufficient. ✓"
 │   └─ WARN → "Missing permissions: [list]. Attach this policy: [json]"
 ├─ write to config:
 │   accounts.spokes[alias].deployment_role_arn = <arn>
 │   accounts.spokes[alias].forwarding_role_arn = <arn>
 └─ "Spoke '{alias}' enrolled with existing roles. No deployment needed."
```

**When to use `import` vs `deploy`:**

| Situation | Command |
|-----------|---------|
| Fresh setup, you control IAM | `mirage roles deploy --all-spokes` |
| Platform team pre-created roles | `mirage roles import <alias> --role-arn ...` |
| Control Tower / landing zone roles exist | `mirage roles import` + policy check |
| Adding a new spoke to existing setup | `mirage roles deploy --spoke <alias>` |
| Tightening permissions after audit | `mirage roles deploy --spoke <alias>` (updates in-place) |
| Rotating ExternalId | `mirage roles deploy --spoke <alias>` (regenerates) |
| Offboarding a spoke | `mirage roles destroy --spoke <alias>` |

### Role Architecture (Security Detail)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  HUB ACCOUNT                                                                │
│                                                                              │
│  mirage-hub-orchestrator-role                                                │
│  ├─ Purpose: the role mirage binary assumes in hub for all hub ops          │
│  ├─ Trust: IAM user/role running the binary (or CI pipeline principal)      │
│  ├─ Permissions: EventBridge, Lambda, SNS, DynamoDB (catalogue), STS        │
│  └─ Condition: optional IP/VPC restriction for CI-only access               │
│                                                                              │
│  Event Bus Policy                                                            │
│  └─ Statement per spoke: Allow events:PutEvents from spoke forwarding role  │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  SPOKE ACCOUNT (one per spoke)                                               │
│                                                                              │
│  mirage-deployment-role                                                      │
│  ├─ Purpose: hub assumes this to run terraform in the spoke                 │
│  ├─ Trust: hub account ONLY + ExternalId = "mirage-<spoke-alias>-<random>"  │
│  ├─ Permissions: create/update/delete ONLY deception resource types         │
│  │   (S3, IAM roles, Lambda, SSM, DynamoDB, SQS, SNS, KMS, ECR, CW Logs)  │
│  ├─ Permission boundary: prevents privilege escalation (can't create IAM    │
│  │   policies broader than the boundary itself)                             │
│  └─ NOT allowed: VPC, EC2 (except stopped bastion), RDS, billing, Org ops  │
│                                                                              │
│  mirage-forwarding-role                                                      │
│  ├─ Purpose: EventBridge rules assume this to forward events to hub bus     │
│  ├─ Trust: events.amazonaws.com (service principal)                         │
│  ├─ Permissions: events:PutEvents on hub bus ARN ONLY                       │
│  └─ NOT allowed: anything else (single-action role)                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Required Permissions per Role (Policy Documents)

**mirage-deployment-role (spoke):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DeceptionResourceManagement",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket", "s3:DeleteBucket", "s3:PutObject", "s3:DeleteObject",
        "s3:PutBucketPolicy", "s3:PutPublicAccessBlock",
        "iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy",
        "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:UpdateFunctionCode",
        "ssm:PutParameter", "ssm:DeleteParameter",
        "dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:PutItem",
        "sqs:CreateQueue", "sqs:DeleteQueue",
        "sns:CreateTopic", "sns:DeleteTopic",
        "kms:CreateKey", "kms:ScheduleKeyDeletion", "kms:CreateAlias",
        "ecr:CreateRepository", "ecr:DeleteRepository",
        "logs:CreateLogGroup", "logs:DeleteLogGroup",
        "events:PutRule", "events:DeleteRule", "events:PutTargets",
        "events:RemoveTargets"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Note on region scoping:** The deployment role is intentionally **not**
> region-restricted. Deception resources may need to be deployed in any region
> to match the target environment's footprint (attackers don't stay in one
> region). The CLI defaults to `us-west-2` via `--region` flag, but operators
> can deploy to any region without needing a role policy change.
>
> If your org requires region restriction at the IAM level, add it as an SCP
> or a permission boundary — not in the role policy itself — so it applies
> uniformly and can be relaxed without redeploying roles.
```

**Trust policy (spoke deployment role):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<HUB_ACCOUNT_ID>:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "mirage-<spoke-alias>-<random-token>"
        }
      }
    }
  ]
}
```

**mirage-forwarding-role (spoke, single-purpose):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "events:PutEvents",
      "Resource": "arn:aws:events:<region>:<HUB_ACCOUNT_ID>:event-bus/<bus-name>"
    }
  ]
}
```

---

## `mirage scenario ...`

### `scenario list [--service | --category | --deployed | --available]`

```
list
 └─ scan remote template repo + local cache
    → table: N | name | service | category | deployed? | spoke(s)
```

Browse available scenarios by:
- **Service** (S3, IAM, Lambda, Secrets Manager, DynamoDB, etc.)
- **Category** (credential-theft, privilege-escalation, data-exfil, lateral-movement)

### `scenario show <n>`

```
show <n>
 ├─ fetch scenario README from template repo
 ├─ display: story, resource chain, attack path, decoy types
 ├─ if deployed → show resolved names from catalogue
 └─ if monitored → show matching detection rule summary
```

### `scenario deploy <n | --all>`

```
deploy
 ├─ GUARD: role == spoke (refuse in hub account)
 ├─ PREFLIGHT:
 │   ├─ Is forwarding deployed in this spoke? (warn if not)
 │   ├─ Is this spoke authorized on hub bus? (fail if not)
 │   └─ Are detection rules deployed in hub? (warn if not)
 │
 ├─ NAMING RESOLUTION:
 │   ├─ Read config.yaml → naming.patterns + naming.overrides
 │   ├─ Apply any CLI flag overrides (--name-prefix, etc.)
 │   └─ Generate scenario-N.tfvars with resolved resource names
 │
 ├─ TEMPLATE ACQUISITION:
 │   ├─ Check local cache (~/.mirage/scenarios/scenario-N/)
 │   ├─ If missing or stale → fetch from configured repo
 │   ├─ Verify template hash against manifest (tamper detection)
 │   └─ Save to local cache
 │
 ├─ TERRAFORM EXECUTION:
 │   ├─ terraform init (provider setup)
 │   ├─ terraform plan -var-file=scenario-N.tfvars
 │   │    (if --dry-run → display plan and stop)
 │   ├─ terraform apply -auto-approve (if --yes) or confirm
 │   └─ capture outputs (resource ARNs)
 │
 ├─ SEED FAKE DATA:
 │   ├─ Upload fake-data/* to deployed resources
 │   ├─ All data marked EXPIRED / fabricated
 │   └─ Skip if --skip-seed
 │
 └─ CATALOGUE REGISTRATION:
     ├─ Write: account, scenario, resource_type, name, arn, timestamp
     └─ Operator identity recorded for audit
```

**Flags:** `--all`, `--skip-seed`, `--name-prefix <p>`, `--spoke <alias>` (for multi-spoke targeting).

### `scenario destroy <n | --all>`

```
destroy
 ├─ GUARD: role == spoke
 ├─ confirm (show resources from catalogue)
 ├─ terraform destroy (per-scenario state)
 ├─ clean seeded data if applicable
 └─ remove from catalogue (mark as destroyed, retain history)
```

### `scenario abuse <n>` ⚠️ DANGEROUS

```
abuse <n>
 ├─ GUARD: role == spoke
 ├─ ⚠️  BIG WARNING: "This fires a REAL alert to SOC"
 ├─ require explicit single <n> (NO --all, NO batch)
 ├─ confirm even if --yes was passed (double-confirm)
 ├─ log: "ABUSE initiated by {principal} at {timestamp}"
 ├─ execute attack chain:
 │   ├─ assume lure role (if applicable)
 │   └─ access decoy resource (triggers CloudTrail event)
 └─ note: "Alert delivered. Check SOC inbox."
```

**No `--all`.** This is by design — see Pattern 6 in design-patterns.

### `scenario status [<n>]`

Per-scenario health (subset of top-level `status`).

---

## `mirage monitor ...`

### `monitor deploy` (Hub account)

```
monitor deploy
 ├─ GUARD: role == hub (refuse in spoke)
 │
 ├─ [1] BRAIN MODULE (terraform apply):
 │       EventBus + Lambda processor + SNS topic + IAM roles
 │       → capture outputs: bus_arn, lambda_arn, sns_topic_arn
 │
 ├─ [2] DETECTION RULES MODULE (terraform apply):
 │       N EventBridge rules (one per deployed scenario)
 │       → reads catalogue for current decoy ARNs
 │       → rules auto-generated from catalogue entries
 │
 ├─ [3] SUBSCRIBE ALERT EMAILS:
 │       aws sns subscribe (idempotent, from config.alerts.emails)
 │
 └─ [4] AUTHORIZE SPOKE(S) ON EVENT BUS:
         aws events put-permission (per spoke in config)
```

**Flags:** `--email <e>` (repeatable), `--authorize <spoke>` (repeatable),
`--brain-only`, `--rules-only`.

### `monitor forwarding` (Spoke account)

```
monitor forwarding
 ├─ GUARD: role == spoke
 ├─ PREFLIGHT: am I authorized on the hub bus?
 │   NO → "Run `mirage monitor authorize <this-spoke>` in hub account first"
 ├─ terraform apply — forwarding module:
 │   ├─ Rule 1: AssumeRole events on lure role ARNs (from catalogue)
 │   ├─ Rule 2: Resource-name pattern matches (from catalogue)
 │   └─ Forwarding IAM role (PutEvents to hub bus only)
 └─ update catalogue: forwarding_deployed = true
```

### `monitor authorize <spoke-id | --all-spokes>` (Hub account)

```
authorize
 ├─ GUARD: role == hub
 └─ aws events put-permission --principal <spoke-id> --action events:PutEvents
    (scoped to central bus ARN)
```

### `monitor subscribe <email>` (Hub account)

```
subscribe → aws sns subscribe --topic-arn <from brain outputs> --email <e>
```

### `monitor status`

```
status
 ├─ Brain module: applied? Lambda healthy?
 ├─ Detection rules: count vs catalogue scenario count
 ├─ Bus permissions: which spokes authorized?
 └─ SNS subscriptions: Confirmed vs PendingConfirmation
```

### `monitor destroy`

```
destroy → confirm → terraform destroy (rules then brain) → revoke bus permissions
```

---

## `mirage status` (end-to-end reconciliation)

```
status
 ├─ HUB PLANE:
 │   ├─ Brain module state
 │   ├─ Detection rules count + health
 │   ├─ Authorized spokes list
 │   └─ Email subscription confirmations
 │
 ├─ SPOKE PLANE (per spoke):
 │   ├─ Forwarding: deployed? rules ENABLED?
 │   ├─ Scenarios: deployed count vs expected
 │   └─ Catalogue consistency (deployed vs registered)
 │
 └─ MATRIX OUTPUT:
     spoke | scenario | deployed | forwarded | rule | alert-path | last-verified
     ──────┼──────────┼──────────┼───────────┼──────┼────────────┼──────────────
     dev   | 1        | ✓        | ✓         | ✓    | ✓          | 2h ago
     dev   | 7        | ✓        | ✓         | ✗    | ✗          | NEVER
     prod  | 1        | ✗        | ✓         | ✓    | ✗          | —
```

**Flags:** `--json`, `--spoke <alias>`, `--full` (includes ARN details).

---

## `mirage verify [--scenario <n>]` (safe drill)

```
verify
 ├─ [optional] announce DRILL to subscribers via SNS
 ├─ select target:
 │   ├─ --scenario <n> → specific decoy
 │   └─ (no flag) → random from catalogue
 ├─ inject synthetic event:
 │   ├─ aws events put-events (CloudTrail-shaped, tagged as drill)
 │   └─ OR: single benign decoy read (e.g., s3 head-object on decoy bucket)
 ├─ poll for Lambda invocation + SNS delivery
 └─ report: round-trip latency (target ~8–12s) → PASS / FAIL
     update catalogue: last_verified = now()
```

**Flags:** `--scenario <n>`, `--drill-notify`, `--timeout <s>`.

---

## `mirage catalogue ...`

### `catalogue show [--spoke <alias>]`
List all tracked resources. Filter by spoke, scenario, or resource type.

### `catalogue sync`
Reconcile catalogue against live AWS state (`terraform state list` + `describe-*`
API calls). Flag orphans and phantoms.

### `catalogue export [--json | --csv]`
Dump for audit, compliance, or SOC ingestion.

---

## `mirage config show | set <key> <value>`

Read or update `~/.mirage/config.yaml`. `set` validates the key and value format.

---

## Command Security Matrix

| Command | Required role | Mutates infra | Requires confirm | Audit logged |
|---------|-------------|---------------|-----------------|--------------|
| `init` | any | yes (local config) | yes | yes |
| `roles deploy` | hub | yes (IAM in spokes) | yes | yes |
| `roles destroy` | hub | yes (IAM removal) | always (double) | yes |
| `roles import` | hub | no (config only) | no | yes |
| `roles status` | hub | no (STS test) | no | no |
| `scenario deploy` | spoke (via role) | yes | yes (unless -y) | yes |
| `scenario destroy` | spoke (via role) | yes | always | yes |
| `scenario abuse` | spoke (via role) | no (reads only) | always (double) | yes |
| `monitor deploy` | hub | yes | yes (unless -y) | yes |
| `monitor forwarding` | spoke (via role) | yes | yes (unless -y) | yes |
| `monitor authorize` | hub | yes (bus policy) | yes (unless -y) | yes |
| `status` | any | no | no | no |
| `verify` | spoke (via role) | no (read/event) | no | yes |
| `catalogue show/export` | any | no | no | no |
| `config show/set` | any | no (local only) | no | no |
