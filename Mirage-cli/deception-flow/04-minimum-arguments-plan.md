# Minimum Arguments Plan

**The deliverable.** The smallest set of arguments/flags `mirage` needs to be
genuinely useful — and how the surface grows across tiers.

Design principle: **derive, don't ask.** Account IDs come from STS + config,
region defaults to `us-west-2`, resource names come from the naming system,
template sources from config. Every value that can be inferred is not an
argument.

---

## Tier 0 — Bootstrap + Read-Only (Zero Risk)

Ship value immediately. No deploys, no mutations. Forces you to build the
foundational packages (`awsctx`, `config`, `discovery`, `catalogue`).

### Commands
```
mirage init                          # bootstrap: auth, hub/spoke, roles, config
mirage scenario list                 # browse available scenarios
mirage scenario show <n>             # scenario details
mirage status                        # end-to-end health (read-only)
mirage config show                   # print current config
```

### Flags at Tier 0
| Flag | Applies to | Why | Default |
|------|-----------|-----|---------|
| `--region` | all | overridable standard | `us-west-2` |
| `--profile` | all | select AWS creds | env |
| `--json` | list/status | CI-friendly output | false |
| `--service` | scenario list | filter by AWS service | (all) |
| `--category` | scenario list | filter by attack category | (all) |

Everything else auto-derived from config + STS identity.

**Value:** First-ever unified view: "what scenarios exist, what's deployed, is
the pipeline healthy?" Zero write path means safe to run anywhere immediately.

---

## Tier 1 — Deploy + Destroy (Core Mutations)

The operational core. Deploy decoys, stand up monitoring, wire everything.

### New commands
```
mirage scenario deploy <n | --all>
mirage scenario destroy <n | --all>
mirage monitor deploy                # brain + rules (hub)
mirage monitor forwarding            # spoke-side forwarding
mirage monitor authorize <spoke-id>  # grant bus access
mirage monitor subscribe <email>
```

### New flags
| Flag | Applies to | Why | Default |
|------|-----------|-----|---------|
| `<n>` (positional) | scenario deploy/destroy | which decoy | required (unless --all) |
| `--all` | scenario deploy/destroy | batch all canonical | false |
| `--yes / -y` | all mutating | skip confirms (CI) | false (prompt) |
| `--dry-run` | all mutating | show terraform plan, don't apply | false |
| `--skip-seed` | scenario deploy | deploy without fake-data upload | false |
| `--name-prefix` | scenario deploy | one-off naming override | config value |
| `--email <e>` | monitor deploy/subscribe | alert recipient | config value |
| `--spoke <alias>` | scenario deploy/forwarding | target specific spoke | current creds |

### Auto-derived (no flags needed)
| Value | Source |
|-------|--------|
| Account ID | `sts get-caller-identity` |
| Account role (hub/spoke) | config.accounts lookup |
| Resource names | naming system (config patterns + overrides) |
| Template path | fetched from configured source (GitHub/local/S3) |
| Hub bus ARN | config.monitoring.event_bus_name + hub account |
| Terraform state path | convention: `~/.mirage/state/<spoke>/<scenario>/` |

### Account-role guard (free safety, no extra args)
- `scenario deploy/destroy` refuses if current account == hub
- `monitor deploy/authorize` refuses if current account != hub
- `monitor forwarding` refuses if current account == hub

**This single check is the highest-value security feature in the entire CLI —
zero user cost, prevents the most dangerous misconfiguration.**

**Value:** Replaces all deploy/destroy scripts with one guarded, ordered binary.

---

## Tier 2 — Observability + Safety (Operational Maturity)

The features that make deception infrastructure **reliable**, not just deployed.

### New commands
```
mirage verify [--scenario <n>]       # safe synthetic drill
mirage scenario abuse <n>            # ⚠️ real attacker simulation
mirage catalogue show                # list tracked resources
mirage catalogue sync                # reconcile state vs live
mirage catalogue export              # audit dump
mirage monitor status                # monitoring health
mirage monitor destroy               # tear down monitoring
mirage config set <key> <value>      # update config
```

### New flags
| Flag | Applies to | Why | Default |
|------|-----------|-----|---------|
| `--drill-notify` | verify | announce "this is a test" first | false |
| `--timeout <s>` | verify | how long to wait for alert round-trip | 30s |
| `--full` | status | include ARN-level detail | false |
| `--spoke <alias>` | catalogue show/sync | filter by spoke | all |
| `--format csv\|json` | catalogue export | output format | json |

### `abuse` constraints (non-negotiable)
- **No `--all`** — must target single scenario number
- **No silent mode** — always prints WARNING banner
- **Double-confirm** — prompts even when `--yes` is passed
- **Audit logged** — operator + timestamp + target recorded in catalogue

**Value:** Proves the detection pipeline works (`verify`), enables controlled red
team exercises (`abuse`), and maintains long-term state accuracy (`catalogue`).

---

## Tier 3 — Scale + Governance (Enterprise)

Multi-spoke fan-out, org-level controls, team collaboration.

### New commands
```
mirage init --add-spoke <id>         # enroll new spoke without full re-init
mirage init --remove-spoke <id>      # decommission spoke (destroy + de-enroll)
mirage monitor deploy --all-spokes   # fan-out forwarding to all spokes
```

### New flags
| Flag | Applies to | Why | Default |
|------|-----------|-----|---------|
| `--parallel <n>` | scenario deploy --all | concurrent terraform applies | 5 |
| `--add-spoke` | init | enroll additional spoke | — |
| `--remove-spoke` | init | decommission spoke | — |
| `--all-spokes` | monitor forwarding | deploy forwarding everywhere | false |

### Capabilities
- Deploy same scenarios across 10+ spokes in parallel
- Add/remove spokes without full re-init
- SCP enforcement at Org level (prevent spoke admins from deleting decoys)
- Shared DynamoDB catalogue for team visibility
- RBAC concept: "who can deploy vs who can only view status"

**Value:** Scales from POC (1 hub + 1 spoke) to enterprise (1 hub + 100 spokes).

---

## Complete Argument Matrix

| Command | Required arg | Key flags | Derived from |
|---------|-------------|-----------|--------------|
| `init` | — | `--hub --spoke --email --prefix --org` | STS identity, org API |
| `scenario list` | — | `--service --category --json` | template source |
| `scenario show` | `<n>` | `--json` | manifest + catalogue |
| `scenario deploy` | `<n>` or `--all` | `-y --dry-run --spoke --name-prefix` | config naming, template fetch |
| `scenario destroy` | `<n>` or `--all` | `-y --spoke` | catalogue + tf state |
| `scenario abuse` | `<n>` | (double-confirm) | catalogue ARNs |
| `monitor deploy` | — | `--email --brain-only --rules-only` | config + catalogue |
| `monitor forwarding` | — | `--spoke` | config + hub bus ARN |
| `monitor authorize` | `<spoke-id>` | — | config |
| `monitor subscribe` | `<email>` | — | brain outputs |
| `status` | — | `--json --spoke --full` | tf state + live AWS |
| `verify` | — | `--scenario --drill-notify --timeout` | catalogue + detection rules |
| `catalogue show` | — | `--spoke --json` | catalogue DB |
| `catalogue sync` | — | `--spoke` | catalogue vs tf state vs AWS |
| `catalogue export` | — | `--format --spoke` | catalogue DB |
| `config show/set` | (set: key value) | — | local file |

---

## Why This Tiering Works (Security Architect Rationale)

1. **Tier 0 ships with zero blast radius** — read-only, can't break anything,
   but immediately reveals "is our deception working?" (the most urgent security
   question).

2. **Tier 1 gates all mutations behind account-role guards** — the most common
   failure (wrong-account deploy) is eliminated before any infra is touched.

3. **Tier 2 addresses the hardest deception problem: silent failure** — `verify`
   proves the alert path works; `catalogue sync` catches drift. Without these,
   you're guessing.

4. **Tier 3 is where deception becomes a platform, not a project** — multi-spoke
   fan-out, team collaboration, org governance. Only needed once the core is
   proven.

5. **`abuse` is deliberately last** — it's the most dangerous command and should
   only be available once the team trusts the tool, the catalogue is accurate,
   and alerting is verified.
