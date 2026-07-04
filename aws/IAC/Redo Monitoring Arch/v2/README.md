# Cloud Deception v2 — Monitoring Architecture

Completely separate from v1. Uses `deception-v2-*` naming for all AWS resources, stack names, and exports. Can run side-by-side with v1 without conflicts.

## Why v2?

A teammate is actively managing v1 resources manually. v2 deploys a parallel monitoring pipeline with:
- New event bus (`deception-v2-global-bus`)
- New Lambda (`deception-v2-event-processor`)
- New SNS topic (`deception-v2-alerts`)
- New forwarding role (`deception-v2-forwarding-role`)
- New detection rules (`deception-v2-detect-XX`)

The decoy scenarios (lure roles, S3 buckets, secrets, etc.) remain UNCHANGED — both v1 and v2 detect the same decoys.

## Folder Structure

```
v2/
├── README.md               ← this file
├── NAMING_MAP.md           ← v1 vs v2 name mapping
├── cleanup-v2.sh           ← delete all v2 resources (revert)
├── csc-prod/               ← CSC Prod (913511275171)
│   ├── monitoring-brain.yaml
│   ├── detection-rules.yaml
│   └── deploy.sh
└── dev-account/            ← Dev account (046574264211)
    ├── forwarding-rule.yaml
    └── deploy.sh
```

## Deploy

### 1. CSC Prod (first)
```bash
cd v2/csc-prod
chmod +x deploy.sh
./deploy.sh
```

### 2. Dev Account (second)
```bash
cd v2/dev-account
chmod +x deploy.sh
./deploy.sh
```

## Revert to v1 Only

```bash
cd v2/
chmod +x cleanup-v2.sh

# Run in dev account first
./cleanup-v2.sh

# Then run in CSC Prod
./cleanup-v2.sh
```

This deletes all v2 stacks and resources. v1 remains untouched.

## Side-by-Side Comparison

| | v1 (teammate manages) | v2 (this folder) |
|---|---|---|
| Stack prefix | `deception-monitoring-*` / `deception-forwarding-*` | `deception-v2-*` |
| Event Bus | `deception-global-event-bus` | `deception-v2-global-bus` |
| Lambda | `deception-event-processor` | `deception-v2-event-processor` |
| SNS | `deception-monitoring-alerts` | `deception-v2-alerts` |
| Forwarding Role | `deception-eventbridge-forwarding-role` | `deception-v2-forwarding-role` |
| Detection Rules | `deception-detect-scenario-XX` | `deception-v2-detect-XX` |
| Dev Rules | various manual | `deception-v2-fwd-sts-roles`, `deception-v2-fwd-resources` |

## Once v2 is Validated

When ready to replace v1:
1. Delete v1 stacks/resources manually
2. Rename v2 resources back to v1 names (use `NAMING_MAP.md`)
3. Or just keep v2 as the new standard
