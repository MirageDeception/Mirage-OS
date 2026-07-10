# Security Architecture Patterns — Mirage CLI

These patterns govern how the `mirage` binary is designed from a security
software architecture perspective. They prioritise: blast-radius containment,
least privilege, auditability, and operational safety.

---

## Pattern 1 — Hub/Spoke Trust Boundary Separation

The system splits across a **trust boundary**: the Hub (monitoring/management)
and Spokes (deception targets). This is not just an organisational convenience —
it's a security architecture choice.

```
┌─────────────────────────────┐     ┌─────────────────────────────┐
│         HUB ACCOUNT         │     │       SPOKE ACCOUNT(S)      │
│  (high-trust, restricted)   │     │  (lower-trust, expendable)  │
│                             │     │                             │
│  • Detection pipeline       │     │  • Deception resources      │
│  • Alerting (SNS/Lambda)    │     │  • Forwarding rules         │
│  • Resource catalogue       │     │  • Fake data                │
│  • Org-level SCPs           │     │  • Cross-account role       │
│                             │     │    (hub → spoke only)       │
│  NEVER deploys decoys       │     │  NEVER touches monitoring   │
└─────────────────────────────┘     └─────────────────────────────┘
```

**Security rationale:**
- If a spoke is compromised, the attacker gains access to decoys (worthless fake
  data) but NOT to the detection pipeline. Monitoring stays intact.
- Hub compromise is more severe but has a smaller attack surface (no public
  resources, no lure endpoints).
- Cross-account roles are unidirectional: Hub assumes into spokes for management;
  spokes can only `PutEvents` to the Hub bus — nothing else.

---

## Pattern 2 — Account-Role Enforcement (Zero-Trust per Command)

Every mutating command starts with identity verification. The CLI does not trust
ambient credentials — it classifies them.

```
resolveAccountRole():
  identity = aws sts get-caller-identity
  account  = identity.Account

  if account == config.accounts.hub     → role = "hub"
  elif account in config.accounts.spokes → role = "spoke"
  else                                   → role = "unknown" → REFUSE

guard(command, requiredRole):
  if currentRole != requiredRole:
      ERROR: "You're in account {account} (role: {currentRole}).
              This command requires role: {requiredRole}.
              Switch profile: aws configure --profile <correct>"
      EXIT 1
```

**Where it's enforced:**
| Command group | Required role | Prevents |
|---------------|--------------|----------|
| `monitor deploy/destroy` | hub | Deploying detection infra in wrong account |
| `scenario deploy/destroy` | spoke | Deploying decoys in the monitoring account |
| `monitor forwarding` | spoke | Deploying forwarding in hub (circular) |
| `monitor authorize` | hub | Granting bus access from wrong side |

**Security rationale:** The #1 operational footgun is running the right command
with the wrong credentials. This guard has zero user cost (no extra flags) and
prevents the most dangerous class of misconfiguration.

---

## Pattern 3 — Config-Driven Naming (Deception Blending)

Decoys must be **indistinguishable from real resources**. If all decoys follow a
predictable `deception-scenario-N` naming pattern, an attacker who discovers one
can enumerate all of them.

**Solution:** Resource names are user-defined via config patterns, not hardcoded
in Terraform templates.

```
CONFIG (intent)                    TERRAFORM (generic template)
naming:                            variable "bucket_name" {
  prefix: "corp"                     default = "__PLACEHOLDER__"
  patterns:                        }
    s3_bucket: "{prefix}-{slug}"
    iam_role: "{prefix}-{slug}-role"
                                   CLI resolves → generates .tfvars:
  overrides:                         bucket_name = "corp-tfstate-backup"
    scenario-1:
      s3_bucket: "infra-terraform-state-prod-backup"
```

**Resolution order (highest wins):**
1. CLI flag (`--name-prefix=...`)
2. Config file (`~/.mirage/config.yaml` → `naming.overrides`)
3. Config patterns (`naming.patterns`)
4. Terraform variable defaults (last resort, placeholders)

**Security rationale:**
- Decoys blend with production naming — attackers can't filter by pattern.
- Templates stay generic and shareable (no org-specific names leak in repos).
- Per-scenario overrides let operators mimic exact real-world resource names.

---

## Pattern 4 — Enforced Deploy Ordering (Dependency Chain)

The detection pipeline has hard dependencies. A decoy deployed without monitoring
is a **silent false negative** — the worst failure mode for a deception system.

```
DEPENDENCY CHAIN:
  Hub brain (EventBus + Lambda + SNS)
       │
       ▼ (outputs: bus_arn, lambda_arn)
  Hub detection rules (uses brain outputs)
       │
       ▼ (bus_arn + put-permission)
  Hub authorizes spoke(s) on the event bus
       │
       ▼ (spoke can now PutEvents)
  Spoke forwarding rules (routes to hub bus)
       │
       ▼ (forwarding active)
  Spoke decoy scenarios (the actual honeypots)
```

**Enforcement:** Each step runs a **preflight check** for its prerequisites:
- `monitor forwarding` → checks bus authorization exists (fails if not)
- `scenario deploy` → checks forwarding is live (warns if not)
- CLI refuses to silently deploy decoys without a working alert path

**Security rationale:** A decoy with no alert path is worse than no decoy —
it gives false confidence. The CLI makes the "happy path" also the "safe path."

---

## Pattern 5 — Resource Catalogue as Security State

The catalogue (SQLite locally or DynamoDB for teams) is not just inventory — it's
the security posture record.

```
┌──────────────────────────────────────────────────────┐
│  CATALOGUE SCHEMA                                    │
│                                                      │
│  account_id | spoke_alias | scenario | resource_type │
│  name | arn | deployed_at | last_verified | status   │
└──────────────────────────────────────────────────────┘

SECURITY USES:
  • Detection rules dynamically reference catalogue ARNs
    (no stale hardcoded ARN lists)
  • `status` reconciles catalogue vs live state
    → finds orphaned decoys (deployed but unmonitored)
    → finds phantom entries (in catalogue but deleted in AWS)
  • `verify` picks a random catalogue entry to test the alert path
  • Audit export for compliance / SOC review
```

**Security rationale:** Deception infra rots silently. Resources get deleted
manually, accounts get decommissioned, rules get disabled. The catalogue is the
single source of "what should exist" that `status` validates against reality.

---

## Pattern 6 — Explicit, Auditable Attack Simulation

Two distinct commands handle "touching the decoy":

| Command | Purpose | Safety level |
|---------|---------|--------------|
| `verify` | Synthetic drill — proves alert path works | SAFE (injects test event, notifies "this is a drill") |
| `abuse <n>` | Real attacker simulation — triggers actual detection | DANGEROUS (fires real alerts to real people) |

**`abuse` safety gates:**
- No `--all` flag (must target single scenario)
- Prints explicit WARNING banner
- Requires confirmation even with `--yes`
- Logs the execution to catalogue with timestamp + operator identity
- Recommended: announce drill to subscribers before running

**Security rationale:** The zero-false-positive guarantee means any alert = real
attack. `abuse` deliberately violates this, so it must be unmistakably
intentional and auditable. A SOC analyst seeing an alert must be able to
distinguish "red team drill at 14:32 by operator X" from "actual compromise."

---

## Pattern 7 — Reconciled End-to-End Status (Detect Drift)

Deception systems fail silently. `status` checks the **complete kill chain**,
not just "is the stack deployed":

```
mirage status:

  HUB PLANE:
    ✓ Brain module applied (EventBus + Lambda + SNS)
    ✓ Detection rules: 19/19 active
    ✓ Spoke-A authorized on bus
    ✗ Spoke-B NOT authorized ← DRIFT DETECTED

  SPOKE-A:
    ✓ Forwarding rules: 2/2 ENABLED
    ✓ Scenarios deployed: 14/19
    ✗ Scenario 7: deployed but NOT in detection rules ← GAP

  MATRIX:
    N | name | deployed | forwarded | rule | alert-path
    1 | ...  | ✓        | ✓         | ✓    | ✓
    7 | ...  | ✓        | ✓         | ✗    | ✗  ← BROKEN
```

**Security rationale:** The most dangerous state for deception infra is
"partially working." `status` turns invisible drift into an explicit, actionable
report. Run it in CI on a schedule.

---

## Pattern 8 — Terraform State Isolation (Blast Radius)

Each logical unit gets its own Terraform state:

```
STATE ISOLATION:
  ~/.mirage/state/
  ├── hub/
  │   ├── brain/terraform.tfstate
  │   ├── detection-rules/terraform.tfstate
  │   └── org-roles/terraform.tfstate
  └── spokes/
      ├── <spoke-alias>/
      │   ├── forwarding/terraform.tfstate
      │   ├── scenario-1/terraform.tfstate
      │   ├── scenario-2/terraform.tfstate
      │   └── ...
      └── <spoke-b>/...

(Or remote backend: S3 bucket with key-per-module)
```

**Security rationale:**
- Destroying one scenario doesn't risk others (no shared state file)
- A corrupted state affects one component, not the whole platform
- Spoke states can be managed by spoke-level operators without hub access
- Supports future: different spoke teams managing their own decoy subsets

---

## Pattern 9 — Least-Privilege Cross-Account Roles

The IAM roles created during `mirage init` follow strict least-privilege:

```
HUB → SPOKE role (for deployment):
  • sts:AssumeRole (from hub to spoke)
  • Scoped to: Terraform operations (create/update/delete decoy resources)
  • NOT scoped to: monitoring, billing, IAM user management
  • Condition: ExternalId = mirage-deployment-{spoke-alias}

SPOKE → HUB permission (for event forwarding):
  • events:PutEvents on the central bus ARN ONLY
  • No other hub access — cannot read rules, modify Lambda, access SNS
  • Principal: the forwarding IAM role in the spoke (not root)
```

**Security rationale:**
- Compromise of the spoke forwarding role = can send events to hub bus (DoS at
  worst, detectable). Cannot modify detection logic.
- Compromise of the hub deployment role = can deploy decoys in spoke (harmless
  fake resources). Cannot access real spoke workloads.

---

## Pattern 10 — Idempotency + Dry-Run + Audit Trail

Every mutating command supports:

| Capability | Purpose |
|------------|---------|
| `--dry-run` | Show terraform plan + resolved names without applying. Peer review before deploy. |
| Idempotent apply | Re-running a deploy with same config = no change. Safe in CI loops. |
| `--yes` | Non-interactive for automation. Still logs who/when/what. |
| Catalogue logging | Every deploy/destroy writes: operator, timestamp, account, scenario, resources. |

**Security rationale:** Auditability. When a SOC team asks "who deployed
scenario 7 in account X last Tuesday?" the catalogue has the answer — even
without CloudTrail (which may be compromised in a deception scenario).

---

## Pattern 11 — Template Supply Chain (Fetch + Verify)

Terraform templates are fetched from a known source, not edited locally:

```
TEMPLATE FLOW:
  1. mirage scenario deploy <n>
  2. CLI checks: is template cached locally?
     NO  → fetch from configured repo (GitHub raw / internal artifact store)
     YES → check hash against remote manifest
  3. If hash mismatch → warn "template updated upstream, re-fetch? Y/N"
  4. Apply from local cache (never directly from network)
```

**Security rationale:**
- Templates are code — supply-chain integrity matters.
- Local cache means offline operation works (air-gapped environments).
- Hash verification prevents silent template tampering.
- Future: sign templates with a GPG key; CLI verifies signature before apply.

---

## Pattern 12 — Multi-Cloud Extensibility (Future-Proofed)

The `mirage init` flow asks for cloud provider. The architecture supports
extension without redesign:

```
internal/
├── providers/
│   ├── aws/        ← current (Terraform + EventBridge + Lambda)
│   ├── azure/      ← future (Terraform + Event Grid + Functions)
│   ├── gcp/        ← future (Terraform + Pub/Sub + Cloud Functions)
│   └── k8s/        ← future (Helm + Falco/admission webhooks)
├── tf/             ← shared Terraform wrapper (provider-agnostic)
└── catalogue/      ← shared (provider column in schema)
```

**Security rationale:** Attackers are multi-cloud; deception should be too. The
provider abstraction lets the team expand coverage without re-architecting.
