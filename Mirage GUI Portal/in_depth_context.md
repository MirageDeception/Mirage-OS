# Project Mirage: In-Depth Technical Blueprint & System Architecture

> **Document Type:** Comprehensive Architectural Specification & Engineering Deep Dive  
> **Applicable Stack:** Next.js 16 (App Router), React 19, TypeScript, Terraform 1.0+, AWS EventBridge, AWS Lambda, Amazon SNS, AWS CloudTrail, AWS STS/IAM.

---

## 1. High-Level System Architecture & Telemetry Dataflow

Project Mirage solves the problem of high alert fatigue and delayed breach discovery by deploying high-fidelity decoy infrastructure across AWS Spoke accounts. Because decoys have zero legitimate business utility, any interaction with them represents unauthorized scanning, lateral movement, or privilege escalation.

```
                              ┌────────────────────────────────────────┐
                              │            Next.js Portal              │
                              │        (Local Command Center)          │
                              └───────────────┬────────────────────────┘
                                              │ 1. AssumeRole (STS)
                                              │ 2. Parameter-injected Terraform
                                              │ 3. Dynamic Rule Generation
                                              ▼
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│ AWS SPOKE ACCOUNT (Target Being Monitored)                                                       │
│                                                                                                  │
│   ┌─────────────────────────────────────────────────────────┐                                    │
│   │ Honey Attack Paths (Terraform Managed)                  │                                    │
│   │  - Fake IAM Roles (e.g. infra-s3-data-readonly-role)    │                                    │
│   │  - Leaked S3 Buckets (e.g. finance-payroll-backup)      │                                    │
│   │  - Decoy SSM Params / Secrets Manager Baits             │                                    │
│   └────────────────────────────┬────────────────────────────┘                                    │
│                                │ Attacker interaction                                            │
│                                ▼                                                                 │
│                       AWS CloudTrail Management Events                                           │
│                                │                                                                 │
│                                ▼                                                                 │
│   ┌─────────────────────────────────────────────────────────┐                                    │
│   │ Tier 1 EventBridge Rules (Dynamically Bin-Packed)       │                                    │
│   │  - Rule: Event_forward_<accountId>_01                   │                                    │
│   │  - Pattern: Filters strictly on decoy resource names    │                                    │
│   └────────────────────────────┬────────────────────────────┘                                    │
│                                │ Matched Events Only                                             │
│                                ▼                                                                 │
│   ┌─────────────────────────────────────────────────────────┐                                    │
│   │ Spoke IAM Forwarding Role                               │                                    │
│   │  - Trust Policy: events.amazonaws.com (Scoped to Rule)  │                                    │
│   │  - Permissions: events:PutEvents on Hub EventBus        │                                    │
│   └────────────────────────────┬────────────────────────────┘                                    │
└────────────────────────────────┼─────────────────────────────────────────────────────────────────┘
                                 │ Cross-Account PutEvents
                                 ▼
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│ AWS HUB ACCOUNT (Security & Logging Brain)                                                       │
│                                                                                                  │
│   ┌─────────────────────────────────────────────────────────┐                                    │
│   │ Central EventBus: Mirage-Hub-Bus                        │                                    │
│   │  - Resource Policy: Grants PutEvents to Spoke Accounts  │                                    │
│   └────────────────────────────┬────────────────────────────┘                                    │
│                                │                                                                 │
│                                ▼                                                                 │
│   ┌─────────────────────────────────────────────────────────┐                                    │
│   │ Tier 2 Static Service Rules (14 Standard Rules)         │                                    │
│   │  - S3 Rule: ListBucket, GetObject, PutObject            │                                    │
│   │  - Secrets Rule: GetSecretValue, DescribeSecret         │                                    │
│   │  - IAM Rule: AssumeRole, ListRoles, GetUser             │                                    │
│   └────────────────────────────┬────────────────────────────┘                                    │
│                                │ Matched Sensitive APIs                                          │
│                                ▼                                                                 │
│   ┌─────────────────────────────────────────────────────────┐                                    │
│   │ Event Processor (AWS Lambda)                            │                                    │
│   │  - Normalizes CloudTrail payload                        │                                    │
│   │  - Correlates with Decoy Metadata                       │                                    │
│   │  - Formats rich attack path alert                       │                                    │
│   └────────────────────────────┬────────────────────────────┘                                    │
│                                │ Publish                                                         │
│                                ▼                                                                 │
│   ┌─────────────────────────────────────────────────────────┐                                    │
│   │ Alert Dispatcher (Amazon SNS: Mirage-Alerts)            │                                    │
│   │  ──► SOC Webhooks / Slack / PagerDuty / Security Email  │                                    │
│   └─────────────────────────────────────────────────────────┘                                    │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The Subprocess & Bash Orchestration Layer

The Next.js portal does not execute Terraform natively in Node.js. Instead, it delegates all infrastructure provisioning and teardown to dedicated shell scripts located in `src/scripts/`:

### 2.1 `src/scripts/deploy-spoke.sh`
- **Signature:** `bash deploy-spoke.sh <scenarioId> <accountId>`
- **Workflow:**
  1. Sets `set -e` for fail-fast execution.
  2. Resolves workspace path: `states/<accountId>/<scenarioId>/`.
  3. Inherits AWS credentials exported into the subshell environment (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_DEFAULT_REGION`).
  4. Runs `terraform init -input=false`.
  5. Executes `terraform apply -auto-approve -input=false`.
  6. Emits machine-readable stdout for the Next.js caller.

### 2.2 `src/scripts/remove-spoke.sh`
- **Signature:** `bash remove-spoke.sh <scenarioId> <accountId>`
- **Workflow:**
  1. Enters `states/<accountId>/<scenarioId>/`.
  2. Runs `terraform destroy -auto-approve -input=false`.
  3. Deletes the local workspace state directory upon successful teardown to reclaim disk space.

### 2.3 `src/scripts/deploy-hub.sh` & `remove-hub.sh`
- Provisions the Centralized Monitoring Brain CloudFormation stack into the designated Hub account:
  - Stack 1: `deception-v2-monitoring-brain` (Global EventBus, Processing Lambda, SNS Topic, IAM execution roles).
  - Stack 2: `deception-v2-service-rules` (14 static EventBridge filtering rules on the central bus).
- Injects SNS subscription endpoints (emails, Slack webhooks) passed from the portal UI.

### 2.4 `src/scripts/sync-scenarios.sh`
- Synchronizes the deception catalog from `https://github.com/MirageDeception/Mirage-OS.git` into `src/templates/mirage-os/`.
- **Modes:**
  - `SYNC_MODE="remote"`: Enforces strict synchronization with `git fetch origin master` and `git reset --hard origin/master`.
  - `SYNC_MODE="local"`: Bypasses network calls, allowing engineers to test and build scenarios locally without internet connectivity or sandboxed token blocks.

---

## 3. Complete Next.js API Route Registry

All API routes live under `src/app/api/`:

| Route Path | Method | Purpose & Core Logic |
| :--- | :--- | :--- |
| `/api/status` | `GET` | Health check endpoint returning system status and deployment locks. |
| `/api/scenarios` | `GET` | Scans `src/templates/mirage-os/aws/scenarios_terraform/`. Reads `details.md` for descriptions and natively parses `variables.tf` to generate dynamic form fields for the catalog UI. |
| `/api/deploy-brain` | `POST` | Assumes the Hub deployment role, executes `deploy-hub.sh`, provisions the central EventBus, Lambda, and SNS topic. |
| `/api/remove-brain` | `POST` | Assumes the Hub deployment role, executes `remove-hub.sh`, tears down the central monitoring stacks. |
| `/api/deploy-spoke` | `POST` | **The Core Engine.** Assumes Spoke role via STS, copies scenario template to `states/<acc>/<scen>/`, runs `deploy-spoke.sh`, parses `terraform output -json decoy_resources`, executes the Bin-Packing compiler, updates `db_inventory.txt`, and generates/updates EventBridge rules in `db_rules.json`. |
| `/api/remove-spoke` | `POST` | Surgical teardown. Queries `db_inventory.txt` for the scenario's decoys, strips them from the active EventBridge JSON pattern, recalculates the `source` array, updates rule status to `'pending'` (Update Available), runs `remove-spoke.sh`, and cleans state. |
| `/api/rules` | `GET` | Returns all rules from `db_rules.json` and active inventory from `db_inventory.txt`, optionally filtered by `?accountId=...`. |
| `/api/deploy-rule` | `POST` | Assumes Spoke role, invokes AWS EventBridge `PutRuleCommand` and `PutTargetsCommand`, pushes the JSON pattern to AWS, updates Spoke forwarding role trust policy via IAM SDK (`UpdateAssumeRolePolicyCommand`), records rule status as `'deployed'`, and logs to `db_history.json`. |
| `/api/reject-rule-update` | `POST` | Reverts pending rule modifications by resetting `eventPattern` back to the saved `deployedPattern` snapshot. |
| `/api/delete-rule` | `POST` | Safely removes an EventBridge rule from AWS. First runs `RemoveTargetsCommand` to detach the central bus target, then runs `DeleteRuleCommand`, and purges the rule record from `db_rules.json`. |
| `/api/inventory-scenarios` | `GET` | Computes active scenario deployments per account by cross-referencing `db_inventory.txt` with template metadata. |
| `/api/history` | `GET` | Reads and returns the audit trail from `db_history.json`. |

---

## 4. The Bin-Packing Algorithm & EventPattern Compiler

The compiler in `src/app/api/deploy-spoke/route.ts` is responsible for packing multiple decoy resources into valid AWS EventBridge patterns without exceeding AWS quotas.

### 4.1 The Quota Ceiling
- **AWS Hard Limit:** 4,096 bytes per `EventPattern`.
- **Safety Threshold:** 4,000 characters.

### 4.2 Mathematical & Compilation Workflow
1. **Extraction:**
   From `terraform output -json decoy_resources`, the API extracts an array:
   ```json
   [
     { "category": "s3", "resources": "prod-financial-archive" },
     { "category": "iam", "resources": "devops-s3-deploy-role" }
   ]
   ```
2. **Category-to-Filter Mapping:**
   The compiler maps categories to CloudTrail event filter paths:
   - `s3`: `detail.requestParameters.bucketName = [ ... ]`
   - `iam`: `detail.requestParameters.roleName = [ ... ]`
   - `secretsmanager`: `detail.requestParameters.secretId = [ ... ]`
   - `ssm`: `detail.requestParameters.name = [ ... ]`
   - `lambda`: `detail.requestParameters.functionName = [ ... ]`
   - `dynamodb`: `detail.requestParameters.tableName = [ ... ]`
   - `sqs`: `detail.requestParameters.queueName = [ ... ]`
3. **Greedy First-Fit Insertion:**
   - Retrieves the Spoke account's latest active rule from `db_rules.json`.
   - If in **Individual Mode**, it immediately allocates a new dedicated rule with `limitReached: true`.
   - In **Scale Mode**, it clones the active pattern and appends the new decoy names into their respective category condition arrays.
   - Generates the unified `source` array (e.g. `["aws.s3", "aws.iam", "aws.ssm"]`).
   - Calculates candidate string length: `L = JSON.stringify(candidatePattern).length`.
4. **Overflow & Sequential Roll-Over:**
   - If $L \le 4000$: Saves the updated pattern to the current rule.
   - If $L > 4000$: 
     1. Marks current rule as `limitReached: true`.
     2. Saves current rule state.
     3. Allocates `Event_forward_<accountId>_<index + 1>`.
     4. Seeds the new rule with the overflowing resources.
5. **Compiled Pattern Example:**
   ```json
   {
     "source": ["aws.s3", "aws.iam"],
     "detail-type": ["AWS API Call via CloudTrail"],
     "detail": {
       "eventSource": ["s3.amazonaws.com", "iam.amazonaws.com"],
       "$or": [
         { "requestParameters": { "bucketName": ["prod-financial-archive", "hr-payroll-backup"] } },
         { "requestParameters": { "roleName": ["devops-s3-deploy-role"] } }
       ]
     }
   }
   ```

---

## 5. Flat-File State Management Specifications

The data access layer is encapsulated in `src/lib/db.ts` and `src/lib/history.ts`.

### 5.1 `db_inventory.txt`
A plain text, pipe-delimited database.  
**Schema:** `AccountId | ScenarioId | RuleName | DecoyName | DecoyCategory`  
**Example:**
```
123456789012 | scenario-1 | Event_forward_123456789012_01 | prod-financial-archive | s3
123456789012 | scenario-1 | Event_forward_123456789012_01 | devops-s3-deploy-role | iam
123456789012 | scenario-2 | Event_forward_123456789012_01 | prod/stripe/api-key | secretsmanager
```

### 5.2 `db_rules.json`
A JSON array of rule records.  
**TypeScript Interface:**
```typescript
interface RuleRecord {
  accountId: string;
  ruleName: string;
  eventPattern: string;       // Current working pattern
  deployedPattern?: string;   // Snapshot of pattern currently live in AWS
  status: 'pending' | 'deployed' | 'failed';
  charCount: number;
  limitReached: boolean;      // True if full (>4000 chars) or individual mode
}
```

### 5.3 `db_history.json`
An append-only audit log.  
**TypeScript Interface:**
```typescript
interface HistoryEntry {
  id: string;
  timestamp: string;
  sessionId: string;
  type: 'terraform_apply' | 'terraform_destroy' | 'rule_push' | 'trust_policy_update' | 'rule_delete';
  scenarioId?: string;
  scenarioName?: string;
  accountId: string;
  ruleName?: string;
  status: 'success' | 'failed';
  error?: string;
}
```

---

## 6. Cross-Account IAM & EventBridge Plumbing

The entire cross-account forwarding security model is anchored by explicit mutual authorization:

### 6.1 Spoke Forwarding Role Trust Policy
When `/api/deploy-rule` pushes an EventBridge rule, it automatically updates the Spoke account's Forwarding Role trust policy to permit EventBridge invocation strictly for that rule ARN:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "events.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": [
            "arn:aws:events:us-west-2:123456789012:rule/Event_forward_123456789012_01"
          ]
        }
      }
    }
  ]
}
```

### 6.2 Hub EventBus Resource Policy
The Hub account's `Mirage-Hub-Bus` contains a resource policy granting `events:PutEvents` permission to the customer Spoke accounts:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSpokeAccountsPutEvents",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:root" },
      "Action": "events:PutEvents",
      "Resource": "arn:aws:events:us-west-2:098765432109:event-bus/Mirage-Hub-Bus"
    }
  ]
}
```
