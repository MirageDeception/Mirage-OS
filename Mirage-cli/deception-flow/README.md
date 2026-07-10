# Mirage — Cloud Deception CLI Design

> **Binary:** `mirage` | **Language:** Go + Cobra | **IaC Engine:** Terraform
> **Architecture:** Hub/Spoke | **Status:** Design only — not yet built.

---

## What is Mirage

A security-first CLI that deploys and manages **cloud deception infrastructure**
(honeypots, lures, decoys) across multiple AWS accounts using a Hub/Spoke model.

The Hub account owns monitoring, alerting, and management. Spoke accounts host
the deception resources. Any interaction with a decoy resource is a confirmed
true positive — zero false positives by design.

Mirage replaces a collection of per-scenario bash scripts and manual
CloudFormation with a single binary that enforces safety, ordering, and
multi-account governance.

---

## Why a CLI (from a security architect's view)

| Problem today | Security risk | Mirage fix |
|---------------|---------------|------------|
| 19 separate `deploy.sh` scripts | No unified access control; anyone with shell access deploys anything | Single binary with account-role guards + audit trail |
| Account IDs hardcoded in scripts | Credential leakage if scripts are shared; wrong-account deploys | Config-driven; accounts resolved at runtime via STS |
| Deploy order is prose in a README | Broken detection pipeline if order is wrong = silent false negatives | Enforced preflight checks; deploy refuses if prerequisites missing |
| No visibility of what's deployed where | Ghost decoys with no monitoring = dead weight; unknown attack surface | Resource catalogue (SQLite/DynamoDB) + reconciled `status` |
| Naming tied to templates | Can't customise names to blend with real resources = attackers spot decoys | Config-driven naming patterns → tfvars injection; templates stay generic |
| No safe drill capability | Can't prove the alert path works without simulating a real attack | `verify` command for synthetic drills; `abuse` gated and loud |

---

## Architecture — Three Planes

```
┌────────────────────── CONTROL PLANE (mirage binary) ──────────────────────┐
│  mirage <verb> ...                                                         │
│  • Config-driven (no hardcoded accounts/names)                             │
│  • Account-role enforcement on every mutating command                      │
│  • Terraform as IaC engine (templates fetched from repo, names via tfvars) │
└────────────────┬──────────────────────────────────────┬───────────────────┘
                 │                                       │
      SPOKE PLANE (N accounts)                HUB PLANE (1 account)
┌──────────────────────────────┐   ┌──────────────────────────────────────┐
│ • Deception scenarios (decoys)│   │ • Central EventBus                    │
│ • EventBridge forwarding rules│──►│ • Detection rules (per-scenario)      │
│ • Cross-account IAM role      │   │ • Lambda processor (enrich + alert)   │
│ • Seeded fake-data            │   │ • SNS alerting                        │
│                               │   │ • Resource catalogue DB               │
└──────────────────────────────┘   └──────────────────────────────────────┘
```

---

## Reading Order

| Doc | What it covers |
|-----|----------------|
| [SINGLE-PAGE-FLOW.md](./SINGLE-PAGE-FLOW.md) | Complete architecture + all flows on one page (start here). |
| [01-design-patterns.md](./01-design-patterns.md) | Security architecture patterns the binary is built on. |
| [02-command-tree.md](./02-command-tree.md) | Full command surface with flags, flows, and safety gates. |
| [03-data-model.md](./03-data-model.md) | Config, naming system, catalogue schema, scenario manifest. |
| [04-minimum-arguments-plan.md](./04-minimum-arguments-plan.md) | Tiered MVP — smallest useful surface → full feature set. |
| [05-build-plan-and-milestones.md](./05-build-plan-and-milestones.md) | Phased implementation plan + security milestone gates. |

Start with [SINGLE-PAGE-FLOW.md](./SINGLE-PAGE-FLOW.md) for the full picture.
Start with [04-minimum-arguments-plan.md](./04-minimum-arguments-plan.md) if you
want the "smallest thing that works" answer.

---

## Hard Constraints (non-negotiable)

| Constraint | Reason |
|------------|--------|
| Hub deploys monitoring only; spokes deploy decoys only | Blast radius containment — monitoring compromise ≠ decoy compromise |
| Deploy order: Hub first → spoke forwarding → spoke decoys | Broken order = silent false negatives (decoy touched, no alert) |
| Zero hardcoded account IDs in code or templates | Portability, secret hygiene, multi-tenant support |
| Naming via config, injected as tfvars | Decoys must blend with real resource names; templates stay generic |
| `abuse` is explicit, loud, single-scenario, no batch | Protects zero-false-positive guarantee; prevents accidental pages |
| All fake data marked EXPIRED/fabricated | IR teams can distinguish deception from real credential leakage |
| Catalogue tracks every deployed resource | Enables audit, status reconciliation, and dynamic detection rules |
