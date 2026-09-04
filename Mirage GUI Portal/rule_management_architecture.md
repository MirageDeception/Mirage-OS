# Project Mirage: EventBridge Rule Engine & User Flexibility Architecture

> **Document Type:** Core Subsystem Specification  
> **Author:** Antigravity Engineering Architecture  
> **Applicable Components:** `src/app/api/deploy-spoke/route.ts`, `src/app/api/deploy-rule/route.ts`, `src/app/api/remove-spoke/route.ts`, `src/app/api/delete-rule/route.ts`, `src/components/RuleEditorPanel.tsx`, `src/components/IndividualRuleToggle.tsx`

---

## 1. Architectural Purpose: The Tier 1 Filtering Mandate

In enterprise cloud deception, deploying decoys is only half the battle. The true operational challenge is **telemetry routing**:
* Traditional security setups send all CloudTrail management logs to a central SIEM or data lake, creating massive ingestion costs and extreme alert fatigue.
* Mirage solves this with a **Dual-Tier Filtering System**. The Spoke-side EventBridge rule serves as the **Tier 1 Filter**: it evaluates CloudTrail events *locally inside the customer's Spoke account* and ensures that **only API calls interacting directly with confirmed decoy resources are forwarded across accounts to the Hub**.

To make this frictionless, Mirage eliminates the need for security engineers to manually write complex JSON EventBridge patterns. It features an automated, in-memory compilation engine paired with a comprehensive user-flexibility control suite.

```
+───────────────────────────────────────────────────────────────────────────────────+
| SPOKE ACCOUNT                                                                     |
|                                                                                   |
|  1. Terraform Apply                                                               |
|        │                                                                          |
|        ▼                                                                          |
|  2. outputs.tf (decoy_resources JSON array)                                       |
|        │                                                                          |
|        ▼                                                                          |
|  3. Next.js API (/api/deploy-spoke) ──► Service-to-Parameter Mapping              |
|        │                                                                          |
|        ▼                                                                          |
|  4. Bin-Packing Compiler (Evaluates pattern length against 4,000 char quota)      |
|        │                                                                          |
|        ├─────────────────────────────┬─────────────────────────────┐              |
|        ▼ (Under limit)               ▼ (Over limit)                ▼              |
|   Packs into Active Rule        Overflows into Next Rule     Individual Mode      |
|   (Event_forward_..._01)        (Event_forward_..._02)       (Dedicated Rule)     |
|        │                                                                          |
|        ▼                                                                          |
|  5. Staging State: "update_available" (Saved to db_rules.json)                    |
|        │                                                                          |
|        ▼                                                                          |
|  6. User Interface: Visual Diff Review / In-Browser Edit / Push to AWS             |
+───────────────────────────────────────────────────────────────────────────────────+
```

---

## 2. How Automated Rule Creation Works (The Engine)

### 2.1 The Data Contract (`outputs.tf`)
The compiler does not guess resource names. When Terraform provisions an attack path, the template's `outputs.tf` exports a normalized JSON array:
```hcl
output "decoy_resources" {
  description = "JSON array of decoy resources for EventBridge rule generation"
  value = jsonencode([
    { category = "s3", resources = aws_s3_bucket.my_decoy_bucket.id },
    { category = "iam", resources = aws_iam_role.my_decoy_role.name },
    { category = "secretsmanager", resources = aws_secretsmanager_secret.my_secret.name }
  ])
}
```
Upon completion of `deploy-spoke.sh`, `/api/deploy-spoke/route.ts` runs `terraform output -json decoy_resources` and ingests this data structure directly into memory.

### 2.2 Multi-Service CloudTrail Parameter Mapping
Different AWS services identify target resources under different keys in the CloudTrail schema. The compiler automatically normalizes these via an internal type-mapping dictionary:

```typescript
const typeMapping: Record<string, string> = {
  s3: 'bucketName',
  secretsmanager: 'secretId',
  sts: 'roleName',
  ssm: 'name',
  iam: 'roleName',
  ecr: 'repositoryName',
  lambda: 'functionName',
  dynamodb: 'tableName',
  sqs: 'queueUrl',
  sns: 'topicArn',
  kms: 'keyId',
  cloudformation: 'stackName'
};
```

The compiler builds an `$or` block inside `detail.requestParameters`:
```json
{
  "source": ["aws.s3", "aws.secretsmanager"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "requestParameters": {
      "$or": [
        { "bucketName": ["prod-financial-archive-backup"] },
        { "secretId": ["prod/payment-gateway/stripe-keys-v2"] }
      ]
    }
  }
}
```

### 2.3 The Mathematical Bin-Packing Compiler
AWS EventBridge rules have a hard limit of **4,096 bytes** per event pattern. Creating one rule per decoy quickly exhausts account rule quotas, while grouping too many decoys together breaks the 4,096-character ceiling.

**The Mirage Bin-Packing Solution:**
1. The compiler enforces `MAX_PATTERN_CHARS = 4000` (leaving a safety buffer).
2. It fetches the Spoke account's latest active rule record from `db_rules.json`.
3. It performs greedy first-fit insertion: appends new decoy names to their category arrays and recalculates `JSON.stringify(candidatePattern).length`.
4. **Automated Overflow:**
   - If `length <= 4000`: Updates the active rule pattern.
   - If `length > 4000`: 
     - Reverts the addition on the current rule.
     - Sets `limitReached = true` and saves the full rule.
     - Spawns a new sequential rule (`Event_forward_<accountId>_<index + 1>`).
     - Continues shifting the remaining resources from the queue into the new rule.

### 2.4 Duplicate Resource Protection
Before generating rules, `/api/deploy-spoke` scans `db_inventory.txt`. If an identical decoy resource name already exists under the same account and category (e.g. re-deploying a scenario), the engine skips adding it to the pattern, emits a duplicate warning in the response, and preserves pattern character limits.

---

## 3. The Complete User Flexibility & Control Suite

Rather than acting as an opaque, rigid automation script, Mirage was architected to give security engineers complete transparency and manual control over every phase of the rule lifecycle.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                               USER FLEXIBILITY MATRIX                            │
├──────────────────────────┬───────────────────────────────────────────────────────┤
│ Feature                  │ User Benefit & Capability                             │
├──────────────────────────┼───────────────────────────────────────────────────────┤
│ 1. Mode Toggle Switch    │ Choose between Grouped (Quota Saver) or Individual    │
│ 2. Staged Deployment     │ Review compiled JSON in local state before AWS push   │
│ 3. Side-by-Side Diff     │ Visual Green/Red line comparison with counter badges  │
│ 4. In-Browser Editor     │ Manually modify JSON patterns directly in the portal  │
│ 5. Instant Revert/Reject │ Discard pending changes and rollback to live snapshot │
│ 6. Surgical Teardown     │ Delete single scenarios without breaking grouped rule │
│ 7. Dynamic Source Prune  │ Automatically strips orphaned AWS services from rule  │
│ 8. Atomic Deletion       │ Detaches targets before deleting rule (no AWS errors) │
│ 9. Auto IAM Trust Sync   │ Automatically updates Spoke Forwarding Role trust     │
│ 10. Fleet Filtering      │ Dropdown selector to filter rules by AWS Account ID   │
└──────────────────────────┴───────────────────────────────────────────────────────┘
```

### 3.1 Individual vs. Scale Mode Switcher (`IndividualRuleToggle.tsx`)
On the catalog page, users can toggle between two distinct architectural approaches:
* **Scale Mode (Grouped - Default):** Consolidates decoys into the minimum number of rules possible using the bin-packing algorithm. Ideal for large enterprise environments with high decoy density.
* **Individual Mode:** Forces the creation of a dedicated, standalone EventBridge rule for each scenario deployment with `limitReached: true`. Ideal for incident response teams wanting isolated scenario attribution.

### 3.2 Staged State Architecture (`update_available`)
Deploying or tearing down a scenario does **not** blindly push changes to AWS immediately:
* The compiler writes the new pattern to local state (`db_rules.json`) and flags the rule with `status: "update_available"`.
* The live pattern currently running in AWS remains completely untouched in the snapshot field `deployedPattern`.
* The user retains full control over the exact moment live AWS infrastructure is modified.

### 3.3 Side-by-Side Visual JSON Diff Viewer (`RuleEditorPanel.tsx`)
Clicking the **Compare Changes** button opens a custom, side-by-side visual diff modal:
* **Left Window:** Shows the live snapshot running in AWS (`deployedPattern`).
* **Right Window:** Shows the proposed compiled pattern (`pattern`).
* **Color-Coded Highlights:** Added decoy lines appear in **green (`+`)**; removed decoy lines appear in **red (`-`)**.
* **Mathematical Line Counters:** Displays exact diff summaries (e.g. `+4 lines added`, `-2 lines removed`).
* **Trailing Comma Normalization:** Standard diff tools falsely flag lines as changed simply because a trailing comma was inserted. Mirage strips trailing commas (`.replace(/,$/, '')`) before computing the mathematical summary, guaranteeing accurate line counts.

### 3.4 Direct In-Browser JSON Rule Editor
Users are not locked into the compiler's output:
* Inside `RuleEditorPanel`, the user can toggle **Edit Mode**.
* They can directly edit the JSON pattern in real time (e.g. adding specific CIDR restrictions, user-agent conditions, or custom CloudTrail event names).
* The editor provides syntax checking before allowing the user to save.

### 3.5 One-Click Rejection & Rollback (`/api/reject-rule-update`)
If an engineer evaluates a proposed rule change or made an error during manual editing:
* Clicking **Reject Update** fires `/api/reject-rule-update`.
* The system discards the working `eventPattern` and restores the exact `deployedPattern` snapshot, reverting the status back to `'deployed'` with zero configuration drift.

### 3.6 Surgical Teardown via the 5-Column Receipt Book
When a scenario is destroyed via Terraform:
* Mirage queries `db_inventory.txt` using the unique 5-column tuple (`AccountId | ScenarioId | RuleName | DecoyName | DecoyCategory`).
* It identifies *only* the decoys belonging to that specific `ScenarioId`.
* It surgically extracts and deletes those decoy strings from the rule's `$or` block, leaving all decoys belonging to other scenarios intact!

### 3.7 Dynamic Source Array Recalculation
If Scenario 3 is destroyed and was the only scenario in that rule utilizing `aws.secretsmanager`:
* Standard automation often leaves `"aws.secretsmanager"` orphaned in the `source` array at the top of the EventBridge rule.
* Mirage's `/api/remove-spoke/route.ts` actively re-scans `db_inventory.txt` for all remaining decoys in that rule, re-derives their distinct categories, and dynamically rebuilds the `source` array. The rule is never over-subscribed to unnecessary CloudTrail traffic.

### 3.8 Safe Atomic Two-Step Rule Deletion (`/api/delete-rule`)
AWS rejects `DeleteRule` API calls if the rule still has attached targets. When all decoys in a rule have been torn down and the rule is deleted:
1. The backend automatically fires `RemoveTargetsCommand` to detach `V2CentralBus`.
2. Only after target detachment succeeds does it fire `DeleteRuleCommand`.
3. It then purges the record from `db_rules.json`.

### 3.9 Zero-Click IAM Forwarding Trust Synchronization
Cross-account EventBridge rules fail unless the Spoke's Forwarding Role trust policy permits `events.amazonaws.com` for that exact rule ARN:
* In standard AWS setups, engineers must manually open the IAM console, edit the trust policy JSON, and add the rule ARN.
* In Mirage, clicking **Push to AWS** invokes `/api/deploy-rule/route.ts`:
  1. Calls `iamClient.send(new GetRoleCommand(...))`.
  2. Decodes the URI-encoded `AssumeRolePolicyDocument`.
  3. Appends the new rule ARN to `Statement[].Condition.ArnEquals["aws:SourceArn"]`.
  4. Calls `UpdateAssumeRolePolicyCommand`.

### 3.10 Multi-Account Fleet Filtering
The Active Rules dashboard features an **Account ID dropdown filter**:
* In multi-tenant environments managing dozens of AWS accounts, security teams can easily filter to inspect rules for a specific account or monitor the global cross-account footprint simultaneously.

---

## 4. Subsystem Code Reference

| Component / Feature | File Location | Key Functions & Lines |
| :--- | :--- | :--- |
| **Compiler & Bin-Packing** | `src/app/api/deploy-spoke/route.ts` | Lines 46–184 (`typeMapping`, `getBasePattern`, `addCondition`, `processResourcesToRules`) |
| **AWS SDK Push & IAM Trust Sync** | `src/app/api/deploy-rule/route.ts` | Lines 37–174 (`PutRuleCommand`, `PutTargetsCommand`, `UpdateAssumeRolePolicyCommand`) |
| **Surgical Teardown & Source Prune** | `src/app/api/remove-spoke/route.ts` | Lines 50–120 (Inventory matching, condition stripping, source recalculation) |
| **Atomic Rule Deletion** | `src/app/api/delete-rule/route.ts` | Lines 30–65 (`RemoveTargetsCommand` ➔ `DeleteRuleCommand`) |
| **Visual Diff Viewer & Editor** | `src/components/RuleEditorPanel.tsx` | Lines 20–37 (`computeDiff`), Lines 48–150 (Diff rendering, in-browser edit, copy, reject) |
| **Mode Switcher Toggle** | `src/components/IndividualRuleToggle.tsx` | Lines 1–60 (`IndividualRuleToggle` component) |
| **Flat-File Data Access Layer** | `src/lib/db.ts` | `getRules`, `saveRuleState`, `getInventory`, `saveInventory`, `overwriteInventory` |
| **Audit Logging** | `src/lib/history.ts` | `appendHistory` (`rule_push`, `rule_teardown`, `trust_policy_update`) |
