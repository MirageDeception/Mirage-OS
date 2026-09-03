# Project Mirage: Specialized Agent Instructions & Operational Rules

> **Target Audience:** Incoming Antigravity AI Agent & Senior Engineering Staff  
> **Repository:** `MirageDeception/Mirage-OS` (Branch: `Mirage_GUI` for portal, `master` for catalog)  
> **Workspace Path:** `/Users/sameerjain/Desktop/Mirage+ for enterprise/portal` (or cloned `Mirage GUI Portal` on company laptop)  
> **Mission:** Lead engineering assistant for Project Mirage, an enterprise-grade cloud deception fabric.

---

## 1. Core Architectural Directives (Non-Negotiable)

### 1.1 Strictly NO External Databases
- **Rule:** Do NOT propose, introduce, or install Postgres, MongoDB, Redis, SQLite, DynamoDB, or any ORM (Prisma, Drizzle, TypeORM).
- **Rationale:** Mirage is designed as an open-source, friction-free tool for enterprise security engineers. Requiring an external database server destroys the single-command "clone and run" developer experience.
- **Implementation:** The entire portal state relies *exclusively* on local flat-file storage handled through `src/lib/db.ts` and `src/lib/history.ts`:
  1. `db_inventory.txt`: 5-column plain text ledger tracking deployed decoys.
  2. `db_rules.json`: JSON dictionary storing EventBridge rule definitions, status, character counts, and diff snapshots.
  3. `db_history.json`: JSON array recording execution logs and error stacks.
- **Self-Healing Requirement:** If any of these files are missing (e.g., fresh clone), the code MUST automatically initialize pristine empty files without crashing. Never remove the self-healing initialization logic in `src/lib/db.ts`.

### 1.2 Subprocess-Driven Terraform Orchestration
- **Rule:** Next.js API routes must **NEVER** directly execute `terraform apply` or `terraform destroy` from Node.js child processes.
- **Rationale:** Terraform executions require workspace isolation, dynamic STS credential environments, variable passing, and exit code trapping. Hardcoding `exec('terraform apply')` inside Node leads to race conditions, zombie processes, and memory leaks.
- **Implementation:** All infrastructure operations MUST route through the dedicated bash scripts in `src/scripts/`:
  - `src/scripts/deploy-spoke.sh <scenarioId> <accountId>`
  - `src/scripts/remove-spoke.sh <scenarioId> <accountId>`
  - `src/scripts/deploy-hub.sh <accountId> <roleArn> [snsEndpoints]`
  - `src/scripts/remove-hub.sh <accountId> <roleArn>`
- **Workspace Isolation:** All Spoke deployments must clone template directories into isolated workspaces under `states/<accountId>/<scenarioId>/`. Never execute Terraform directly inside `src/templates/`!

### 1.3 The Dual-Tier Telemetry Filtering Law
Any new scenario or service added to the platform must strictly conform to the **Dual-Tier Filtering Model**:
1. **Tier 1 (Spoke Account Edge):**
   - Implemented via dynamic Spoke-side EventBridge rules (`Event_forward_<accountId>_<index>`).
   - Filters CloudTrail events **strictly by DECOY RESOURCE NAMES** (e.g., specific bucket name, role name, parameter path).
   - Only events matching exact decoy targets are permitted to cross the AWS account boundary to the Hub.
2. **Tier 2 (Hub Account Brain):**
   - Implemented via 14 static EventBridge service rules sitting on the central `Mirage-Hub-Bus`.
   - Filters incoming Spoke events **strictly by SENSITIVE API ACTIONS** (e.g., `s3:GetObject`, `secretsmanager:GetSecretValue`, `sts:AssumeRole`).
   - Forwards matches to the processing Lambda, which enriches the alert and fires Amazon SNS (`Mirage-Alerts`).

---

## 2. Terraform Scenario Contract

Every deception scenario in `scenarios_terraform/` or `src/templates/mirage-os/aws/scenarios_terraform/` MUST adhere to the following file and coding structure:

### 2.1 Contextual Variables (`variables.tf`)
Do NOT name variables by their AWS service type (e.g., `var.s3_bucket_name` or `var.iam_role_name`). When a scenario creates multiple resources of the same type, service-based naming creates severe ambiguity.  
Always use **Contextual Variables** based on the attack path role:
```hcl
variable "discovery_resource_name" {
  description = "The initial bait resource discovered by the attacker"
  type        = string
  default     = "infra-public-backup-bucket"
}

variable "execution_resource_name" {
  description = "The intermediate compute or role used to pivot"
  type        = string
  default     = "infra-data-sync-exec-role"
}

variable "target_resource_name" {
  description = "The high-value target or sensitive datastore targeted"
  type        = string
  default     = "finance-payroll-database"
}
```

### 2.2 Mandatory `decoy_resources` Output (`outputs.tf`)
The automated EventBridge rule compiler in `/api/deploy-spoke/route.ts` reads `terraform output -json decoy_resources`. If this block is missing, **no EventBridge rule will be generated for the scenario!**

Every scenario `outputs.tf` must export a JSON-encoded array:
```hcl
output "decoy_resources" {
  description = "JSON array of decoy resources for EventBridge rule generation"
  value = jsonencode([
    {
      category  = "s3"
      resources = aws_s3_bucket.my_decoy_bucket.id
    },
    {
      category  = "iam"
      resources = aws_iam_role.my_decoy_role.name
    },
    {
      category  = "ssm"
      resources = aws_ssm_parameter.my_param.name
    }
  ])
}
```

#### Category Mapping Rules:
| Category String | CloudTrail Event Source | Resource Attribute to Use |
| :--- | :--- | :--- |
| `s3` | `s3.amazonaws.com` | `.id` (Bucket Name) |
| `iam` | `iam.amazonaws.com` | `.name` (Role Name, NOT ARN) |
| `secretsmanager` | `secretsmanager.amazonaws.com` | `.name` (Secret Name) |
| `ssm` | `ssm.amazonaws.com` | `.name` (Parameter Path) |
| `sts` | `sts.amazonaws.com` | `.name` (Assumed Role Name) |
| `ec2` | `ec2.amazonaws.com` | `.id` (Instance ID) |
| `ecr` | `ecr.amazonaws.com` | `.name` (Repository Name) |
| `lambda` | `lambda.amazonaws.com` | `.function_name` (Function Name) |
| `dynamodb` | `dynamodb.amazonaws.com` | `.name` (Table Name) |
| `sqs` | `sqs.amazonaws.com` | `.name` (Queue Name) |
| `sns` | `sns.amazonaws.com` | `.name` (Topic Name) |
| `logs` | `logs.amazonaws.com` | `.name` (Log Group Name) |
| `kms` | `kms.amazonaws.com` | `.id` (Key ID / Key ARN) |
| `cloudformation` | `cloudformation.amazonaws.com` | `.name` (Stack Name) |

### 2.3 Instant Deletion Configuration (AWS Secrets Manager)
To prevent Terraform teardowns from hanging on 7–30 day AWS soft-delete windows, every `aws_secretsmanager_secret` MUST include:
```hcl
resource "aws_secretsmanager_secret" "decoy" {
  name                            = var.discovery_resource_name
  recovery_window_in_days         = 0
  force_delete_without_recovery   = true
}
```

---

## 3. Dynamic EventBridge Rule Engine & Bin-Packing Rules

The rule compiler in `src/app/api/deploy-spoke/route.ts` and `src/app/api/deploy-rule/route.ts` governs telemetry routing:

1. **The 4,000-Character Quota Ceiling:**
   - AWS EventBridge imposes a hard limit on `EventPattern` JSON strings (4,096 bytes).
   - In **Bin-Packing Mode (Scale Mode)**, the compiler MUST calculate `JSON.stringify(pattern).length`.
   - If adding a decoy exceeds `4,000` characters, the current rule is marked `limitReached: true`, saved, and a new sequential rule (`Event_forward_<accountId>_<nextIndex>`) is created.
2. **Individual Rule Mode:**
   - If the user toggles "Individual Rules" in the UI, every scenario deployment forces a dedicated rule with `limitReached: true` so no subsequent scenarios pack into it.
3. **The 5-Column Ledger Synchronization:**
   - Whenever decoys are registered, write them to `db_inventory.txt` using the exact pipe-delimited format:
     `AccountId | ScenarioId | RuleName | DecoyName | DecoyCategory`
4. **Surgical Teardown & Source Recalculation:**
   - When tearing down a scenario, never delete the rule unless it becomes completely empty!
   - Delete only the specific decoy strings from the `detail.requestParameters` array.
   - **Crucial:** Re-scan `db_inventory.txt` for all remaining decoys in that rule and dynamically rebuild the `source` array (e.g. `["aws.s3", "aws.iam"]`). Do NOT leave orphaned service identifiers in `source`!
   - Update rule status to `'pending'` with `deployedPattern` intact so the UI shows an **Update Available ⚠️** diff.
5. **Atomic Rule Deletion Order:**
   - When a rule is completely empty, AWS will reject `DeleteRuleCommand` if targets exist.
   - **Always execute `RemoveTargetsCommand` first**, then `DeleteRuleCommand`.
6. **Automated IAM Forwarding Trust Policy Updates:**
   - Whenever a rule is pushed to AWS (`/api/deploy-rule`), the Spoke's `forwardingRoleArn` trust policy must allow `events.amazonaws.com` to assume it.
   - The route must fetch `AssumeRolePolicyDocument`, decode the URI JSON, append the rule ARN to `Statement[].Condition.ArnEquals["aws:SourceArn"]`, and call `UpdateAssumeRolePolicyCommand`.

---

## 4. UI/UX & Frontend Engineering Standards

- **Next.js 16 App Router:** All client components with state/effects must begin with `"use client";`.
- **Form Controls:** NEVER bind a `<input value={x} />` without an `onChange` handler (avoids React console warnings). Use `defaultValue` or provide an explicit `onChange`.
- **Visual Identity:**
  - Backgrounds: `#050505` with fixed radial-dot red grid (`globals.css`).
  - Cards: `.glass-panel` (`background: rgba(15, 15, 15, 0.85); backdrop-filter: blur(12px)`).
  - Accents: Red gradient (`var(--accent-red): #ef4444`, `var(--accent-dark-red): #991b1b`).
- **Diff Viewer:** The JSON diff modal calculates added (`+`) and removed (`-`) lines. Always strip trailing commas (`.replace(/,$/, '')`) before computing line counts to prevent false-positive diff inflation.
- **Outside Click Listeners:** Dropdowns (like the notification center bell drawer) must attach an event listener to `document` on mount to dismiss when clicking outside the panel.

---

## 5. Environment & Sandbox Handling

1. **Dev Server Execution:**
   - The dev server runs via `npm run dev` (Turbopack) on `http://localhost:3000`.
   - If port 3000 is occupied, check `lsof -ti :3000` or kill the stuck PID before launching.
2. **GitHub Scenario Sync Toggle:**
   - `src/scripts/sync-scenarios.sh` syncs scenarios from `MirageDeception/Mirage-OS`.
   - In sandboxed environments or offline corporate networks, Git network calls fail.
   - Set `SYNC_MODE="local"` in `src/scripts/sync-scenarios.sh` to bypass network fetches and read directly from the local template folder.
   - In live production, set `SYNC_MODE="remote"`.

---

## 6. Zero-Leakage Data Security Checklist

Before ever committing or pushing code to any GitHub branch:
1. **AWS Account IDs:** Search for 12-digit numbers. Placeholders must be `123456789012` or `098765432109`.
2. **AWS Credentials:** Grep for `AKIA`, `ASIA`, private keys, or session tokens.
3. **Local Paths:** Ensure no hardcoded `/Users/...` paths exist in committed code; use `process.cwd()` or `path.join()`.
4. **Git Tracking:** Verify that `.gitignore` contains:
   - `.next/`, `node_modules/`
   - `states/` (isolated Terraform state directories)
   - `db_inventory.txt`, `db_rules.json`, `db_history.json`
   - `docs/` (internal engineering notes)
   - `*.swp` (editor swap files)
