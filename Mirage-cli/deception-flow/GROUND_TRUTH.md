# GROUND TRUTH — Mirage CLI Design (Anti-Hallucination Guardrail)

> Purpose: keep any model from inventing facts about the Mirage CLI design.
> If a fact isn't in this file and isn't in a file you opened, don't state it.

---

## HARD FACTS

| Fact | Value |
|------|-------|
| Binary name | **`mirage`** |
| Language | Go + Cobra |
| IaC engine | **Terraform** (NOT CloudFormation) |
| Architecture | **Hub/Spoke** (Hub = monitoring + management, Spoke = deception targets) |
| Status | **DESIGN ONLY — not built.** Do not claim it can be run. |
| Cloud (current) | AWS |
| Cloud (future) | Azure, GCP, K8s (designed for extensibility) |
| Region (default) | `us-west-2` |
| Account IDs in code/templates | **NONE** — all config-driven, no hardcoded values |
| Naming approach | Config-driven patterns + tfvars injection. Templates use placeholders. |
| State backend | Per-module Terraform state isolation |
| Resource catalogue | SQLite (local) or DynamoDB (team) |
| Template source | Fetched from GitHub/S3/local — integrity verified via SHA256 |

---

## ARCHITECTURE RULES

| Rule | Detail |
|------|--------|
| Hub account | Owns: EventBus, Lambda, SNS, detection rules, catalogue DB, Org roles |
| Spoke account(s) | Owns: Decoy scenarios, forwarding rules, cross-account IAM role |
| Hub never deploys decoys | Blast radius separation — monitoring compromise ≠ decoy compromise |
| Spokes never touch monitoring | Can only PutEvents to hub bus — nothing else |
| Cross-account direction | Hub assumes into spokes for management; spokes forward events to hub |

---

## DEPLOY ORDER (non-negotiable)

```
1. mirage init         → bootstrap (auth, roles, config, catalogue)
2. monitor deploy      → hub: brain (EventBus + Lambda + SNS) → detection rules
3. monitor authorize   → hub: grant spoke(s) bus access
4. monitor forwarding  → spoke: forwarding rules → hub bus
5. scenario deploy     → spoke: decoy resources + fake data + catalogue registration
```

Spoke forwarding won't work until hub authorizes.
Decoys without monitoring = silent false negatives (worst failure mode).

---

## NAMING SYSTEM

| Aspect | Detail |
|--------|--------|
| Where names are defined | `~/.mirage/config.yaml` → `naming.patterns` + `naming.overrides` |
| How names reach Terraform | CLI generates `.tfvars` file; templates use `variable` with placeholder defaults |
| Precedence (highest wins) | CLI flag → config override → config pattern → terraform default |
| Why | Decoys must blend with real resource names; templates stay generic and shareable |
| Per-scenario overrides | `naming.overrides.scenario-N.<resource_type>` for exact name mimicry |

---

## COMMAND SURFACE

```
mirage
├── init
├── scenario (list | show | deploy | destroy | abuse | status)
├── monitor (deploy | forwarding | authorize | subscribe | status | destroy)
├── status
├── verify
├── catalogue (show | sync | export)
└── config (show | set)
```

---

## SAFETY CONSTRAINTS

| Constraint | Enforcement |
|------------|-------------|
| Wrong-account prevention | Account-role guard (every mutating command checks STS identity vs config) |
| Deploy ordering | Preflight checks; spoke commands fail if hub prerequisites missing |
| `abuse` safety | No `--all`, single scenario only, double-confirm, full audit log |
| Template integrity | SHA256 hash verification against remote manifest before apply |
| Fake data convention | All seeded data marked EXPIRED/fabricated |
| Catalogue as audit trail | Every operation logged: operator, timestamp, target, result |

---

## DO / DON'T

**DO**
- Refer to the binary as `mirage` (not `decoy`)
- Say Terraform (not CloudFormation)
- Say Hub/Spoke (not CSC Prod / dev account)
- Use config-driven language (no hardcoded account IDs anywhere)
- Distinguish design (this folder) from existing implementation (scenarios/ + Redo Monitoring Arch/)
- Say "19 canonical scenarios" with the caveat (10 empty, 20/21 extras)

**DON'T**
- Don't hardcode account IDs in any design doc or example
- Don't claim `mirage` exists or can be executed — it's a design
- Don't say CloudFormation (the CLI uses Terraform; existing scripts use CFN)
- Don't assume naming — it's always config-driven with user control
- Don't put secrets, real emails, or real account IDs in design docs
- Don't describe `abuse` as safe or automated — it's dangerous and gated
