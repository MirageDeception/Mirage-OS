# Build Plan & Milestones

How to build `mirage` — phased so each milestone is independently shippable,
testable, and provides security value.

---

## Language & Libraries

**Go + Cobra** — single binary, cross-compile for Linux/macOS/Windows, no
runtime dependencies on the operator's machine (except Terraform + AWS CLI).

| Concern | Choice | Rationale |
|---------|--------|-----------|
| CLI framework | `spf13/cobra` | Subcommand tree, flags, help generation, shell completion. |
| Config | `gopkg.in/yaml.v3` | `~/.mirage/config.yaml` load/save/validate. |
| Terraform | `os/exec` → `terraform` CLI | Terraform handles provider auth, state, plan/apply. No SDK needed. |
| AWS (read-only) | `aws-sdk-go-v2` | For `status`, `verify`, `catalogue sync` — structured output needed. |
| AWS (mutations) | `terraform` via CLI | All infra changes go through Terraform (auditability, state tracking). |
| Database | `modernc.org/sqlite` (CGo-free) | Local catalogue. Zero external dependencies. |
| DynamoDB | `aws-sdk-go-v2/service/dynamodb` | Team/shared catalogue backend. |
| HTTP | `net/http` | Fetch templates from GitHub/S3. |
| Hashing | `crypto/sha256` | Template integrity verification. |
| Output/color | `fatih/color` + `olekukonko/tablewriter` | Readable CLI output + status matrices. |
| Testing | `testing` + `testify` | Unit + integration tests. |

### Why Terraform (not raw AWS CLI)

| Aspect | Terraform | AWS CLI (old approach) |
|--------|-----------|----------------------|
| State tracking | Built-in (tfstate) | None — must query AWS |
| Drift detection | `terraform plan` | Manual describe calls |
| Dependency resolution | Automatic | Script ordering |
| Rollback | `terraform destroy` knows exact resources | Must track manually |
| Multi-resource deploy | Atomic (all-or-nothing per apply) | Sequential, partial failure |
| Idempotency | Native | Depends on `--no-fail-on-empty-changeset` |
| Cross-provider (future) | Same tool for Azure/GCP | Provider-specific CLIs |

---

## Project Layout

```
mirage/
├── cmd/
│   └── mirage/
│       └── main.go                     ← entry point, root command setup
├── internal/
│   ├── cmd/                            ← Cobra command handlers (thin)
│   │   ├── root.go                     ← global flags, pre-run hooks
│   │   ├── init.go                     ← bootstrap wizard
│   │   ├── scenario.go                 ← list/show/deploy/destroy/abuse
│   │   ├── monitor.go                  ← deploy/forwarding/authorize/subscribe
│   │   ├── status.go                   ← end-to-end reconciliation
│   │   ├── verify.go                   ← synthetic drill
│   │   ├── catalogue.go                ← show/sync/export
│   │   └── config.go                   ← show/set
│   ├── awsctx/                         ← AWS context resolution
│   │   ├── identity.go                 ← STS get-caller-identity
│   │   ├── role.go                     ← hub/spoke/unknown classification
│   │   └── guard.go                    ← role enforcement middleware
│   ├── config/                         ← Configuration management
│   │   ├── schema.go                   ← config struct + validation
│   │   ├── loader.go                   ← read/write ~/.mirage/config.yaml
│   │   └── defaults.go                 ← sensible defaults
│   ├── naming/                         ← Resource naming engine
│   │   ├── resolver.go                 ← pattern interpolation
│   │   ├── variables.go                ← {prefix}, {slug}, etc. definitions
│   │   └── tfvars.go                   ← generate .tfvars from resolved names
│   ├── discovery/                      ← Scenario discovery
│   │   ├── scanner.go                  ← walk template source, parse manifests
│   │   ├── manifest.go                 ← scenario.yaml struct
│   │   └── filter.go                   ← by service, category, deployed status
│   ├── tf/                             ← Terraform operations wrapper
│   │   ├── runner.go                   ← init/plan/apply/destroy/output
│   │   ├── state.go                    ← state path management (per-module isolation)
│   │   └── vars.go                     ← variable file generation
│   ├── templates/                      ← Template acquisition
│   │   ├── fetcher.go                  ← GitHub/S3/local fetch
│   │   ├── cache.go                    ← local cache management
│   │   └── integrity.go                ← SHA256 verification against manifest
│   ├── catalogue/                      ← Resource catalogue
│   │   ├── store.go                    ← interface (SQLite + DynamoDB implement)
│   │   ├── sqlite.go                   ← local backend
│   │   ├── dynamodb.go                 ← team/shared backend
│   │   ├── operations.go              ← register/deregister/sync/verify-update
│   │   └── audit.go                    ← operations_log writes
│   ├── monitor/                        ← Monitoring orchestration
│   │   ├── brain.go                    ← EventBus + Lambda + SNS deploy
│   │   ├── rules.go                    ← detection rules (generated from catalogue)
│   │   ├── forwarding.go              ← spoke-side forwarding setup
│   │   ├── authorize.go               ← bus permission management
│   │   └── subscribe.go               ← SNS email subscription
│   └── verify/                         ← Alert verification
│       ├── drill.go                    ← synthetic event injection
│       ├── poll.go                     ← wait for Lambda/SNS delivery
│       └── report.go                   ← PASS/FAIL + latency measurement
├── pkg/
│   └── models/                         ← Shared types (Scenario, Resource, etc.)
├── go.mod
├── go.sum
├── Makefile                            ← build, test, lint, release targets
└── README.md
```

---

## Milestones

### M0 — Foundation + Read-Only (Tier 0)

**Goal:** Ship a binary that shows deception posture without modifying anything.

**Build:**
- `awsctx`: STS identity, role classification (hub/spoke/unknown)
- `config`: schema, loader, writer, validator
- `naming`: pattern resolver (needed for `show` to display resolved names)
- `discovery`: template source scanner, manifest parser
- `catalogue`: SQLite schema creation, basic queries

**Ship:**
- `mirage init` (interactive bootstrap)
- `mirage scenario list` (browse available scenarios)
- `mirage scenario show <n>` (scenario details)
- `mirage status` (read-only, queries live AWS state)
- `mirage config show`

**Security gate:** No write operations. Safe to run in any account at any time.
The `init` command creates local config + catalogue DB only.

**Value:** First unified view of "what's deployed and is it monitored?"

---

### M1 — Terraform Deploy Engine (Tier 1 core)

**Goal:** Deploy and destroy decoy scenarios with full safety.

**Build:**
- `tf`: Terraform runner (init/plan/apply/destroy), state path management
- `templates`: GitHub fetcher, local cache, integrity verification
- `naming/tfvars`: generate .tfvars from resolved names
- `catalogue/operations`: register resources after deploy, deregister on destroy
- `catalogue/audit`: log all operations
- `awsctx/guard`: enforce account-role on every mutating command

**Ship:**
- `mirage scenario deploy <n|--all>` (fetch → resolve → plan → apply → seed → register)
- `mirage scenario destroy <n|--all>` (confirm → destroy → deregister)
- `--dry-run` on both (shows plan without applying)
- `--yes` for CI automation

**Security gate:**
- Account-role guard blocks spoke commands in hub and vice versa
- Template integrity verified before apply (SHA256 check)
- All operations audit-logged in catalogue
- Fake-data seeding marks all content as EXPIRED/fabricated

**Value:** Replaces 19 individual `deploy.sh` scripts with one safe command.

---

### M2 — Monitoring Orchestration (Tier 1 complete)

**Goal:** Deploy the full detection pipeline with enforced ordering.

**Build:**
- `monitor/brain`: EventBus + Lambda + SNS terraform module
- `monitor/rules`: detection rules generated from catalogue ARNs
- `monitor/forwarding`: spoke-side forwarding terraform module
- `monitor/authorize`: EventBus put-permission wrapper
- `monitor/subscribe`: SNS subscription management
- Preflight checks (bus authorization, forwarding prerequisite)

**Ship:**
- `mirage monitor deploy` (brain → rules → subscribe → authorize)
- `mirage monitor forwarding` (spoke-side, with preflight)
- `mirage monitor authorize <spoke-id>`
- `mirage monitor subscribe <email>`
- `mirage monitor status`
- `mirage monitor destroy`

**Security gate:**
- Deploy order enforced: spoke commands fail if hub prerequisites missing
- Detection rules auto-generated from catalogue (no stale ARN lists)
- Bus permissions scoped to PutEvents only

**Value:** Replaces monitoring deploy scripts + encodes deploy order that was
previously prose in a README.

---

### M3 — Verification + Observability (Tier 2)

**Goal:** Prove the detection pipeline works. Catch drift.

**Build:**
- `verify`: synthetic event injection, Lambda/SNS poll, PASS/FAIL reporting
- `catalogue/sync`: reconcile catalogue vs terraform state vs live AWS
- Catalogue export (JSON/CSV for audit)
- `status` enhanced: last_verified timestamps, drift detection

**Ship:**
- `mirage verify [--scenario <n>]` (safe end-to-end drill)
- `mirage catalogue show` / `catalogue sync` / `catalogue export`
- Enhanced `mirage status` (includes verification timestamps + drift flags)

**Security gate:**
- `verify` uses drill-tagged events (distinguishable from real attacks)
- `catalogue sync` detects orphaned decoys (deployed but unmonitored)
- Round-trip latency measured (target: 8–12s)

**Value:** Answers "is our deception actually working RIGHT NOW?" — not just
"is stuff deployed."

---

### M4 — Attack Simulation (Tier 2 complete)

**Goal:** Controlled, auditable attacker simulation for red team exercises.

**Build:**
- `scenario abuse <n>`: execute attack chain per scenario
- Double-confirm gate (even with --yes)
- Audit logging (who/when/which scenario)
- Drill notification system (optional pre-announcement to subscribers)

**Ship:**
- `mirage scenario abuse <n>` (real attacker simulation)
- Pre-drill notification option
- Full audit trail in catalogue

**Security gate:**
- No `--all` — single scenario only
- Always prints WARNING banner
- Double confirmation (can't accidentally page SOC)
- Full audit: operator principal + timestamp + target logged

**Value:** Enables controlled red team exercises with full accountability.

---

### M5 — Scale + Governance (Tier 3)

**Goal:** Multi-spoke fan-out, org-level controls, team operations.

**Build:**
- Parallel terraform applies (goroutine pool with `--parallel` limit)
- Spoke enrollment/decommissioning without full re-init
- DynamoDB catalogue backend (team shared state)
- SCP templates for org-level decoy protection
- (Future) RBAC model: viewer vs operator vs admin

**Ship:**
- `mirage init --add-spoke` / `--remove-spoke`
- `mirage scenario deploy --all --parallel 10` (fan-out)
- `mirage monitor forwarding --all-spokes`
- DynamoDB catalogue (shared across team members)
- SCP deployment via init (protect decoys from spoke admins)

**Security gate:**
- SCPs prevent spoke-level admins from deleting deception resources
- Shared catalogue gives SOC visibility into all spokes
- Parallel deploys respect rate limits (no AWS throttling)

**Value:** Scales from POC (1+1) to enterprise (1+100).

---

## Security Testing Strategy (per milestone)

| Milestone | Security tests |
|-----------|---------------|
| M0 | Guard refuses wrong-role access; config stores no secrets; STS failure handled gracefully |
| M1 | Template integrity rejects tampered files; guard blocks hub-account deploy; audit log captures all operations |
| M2 | Preflight rejects unauthed spokes; bus permission scoped correctly; rules match catalogue ARNs only |
| M3 | Verify distinguishes drill from real; sync catches orphaned decoys; export contains no secrets |
| M4 | Abuse double-confirms; audit trail complete; no batch abuse possible |
| M5 | SCP prevents decoy deletion; parallel deploy doesn't corrupt state; DynamoDB access scoped to catalogue table |

---

## Definition of Done

| Tier | Done when… |
|------|-----------|
| Tier 0 (M0) | `init` writes config; `status` shows live posture; zero write operations |
| Tier 1 (M1–M2) | Deploy/destroy any scenario + full monitoring pipeline, guarded by account-role, ordered by preflight |
| Tier 2 (M3–M4) | `verify` proves alerts fire; `catalogue sync` catches drift; `abuse` is controlled + audited |
| Tier 3 (M5) | 10+ spokes managed in parallel; shared catalogue; org-level SCP protection |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Wrong-account deploy | Monitoring in spoke = useless; decoy in hub = confusing | Account-role guard (M1), zero extra args |
| Silent false negative | Decoy touched, no alert = worst failure | `verify` (M3) + reconciled `status` (M0) |
| Template supply chain | Tampered template deploys malicious resources | SHA256 integrity check + local cache (M1) |
| Accidental `abuse` | Real alerts fire, SOC investigates a non-event | No `--all`, double-confirm, pre-drill notify (M4) |
| Catalogue drift | Catalogue says deployed but AWS disagrees | `catalogue sync` reconciliation (M3) |
| State file corruption | Terraform can't manage the resource anymore | Per-scenario state isolation (M1) |
| Naming pattern collision | Two scenarios get same resource name | Resolver validates uniqueness before apply (M1) |
| Spoke compromise | Attacker in spoke sees deception infra | Decoys are worthless by design; hub stays isolated |

---

## First Thing to Build

Start with **M0**. It's:
- Pure read (can't break anything)
- Forces you to build `awsctx` + `config` + `naming` + `discovery` + `catalogue`
  (every later milestone reuses these)
- Ships real security value immediately ("is my deception posture healthy?")
- Can be shared with SOC/leadership before any deploy capability exists

Everything downstream is additive on top of M0's foundation.
