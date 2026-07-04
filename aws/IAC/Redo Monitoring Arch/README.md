# Cloud Deception — Monitoring Architecture

Two-layer detection system for cloud deception decoys across AWS accounts.

## Architecture

```
DEV ACCOUNT (046574264211) — where decoys live
┌──────────────────────────────────────────────────────────────┐
│  Default Event Bus                                           │
│       │                                                      │
│  2 Forwarding Rules:                                         │
│    Rule 1: STS AssumeRole on 23 lure role ARNs               │
│    Rule 2: All other services matching decoy resource names   │
│       │                                                      │
│  1 IAM Role: deception-eventbridge-forwarding-role           │
│  (trust: only deception-fwd-* rules in this account)         │
└───────┼──────────────────────────────────────────────────────┘
        │ events:PutEvents (only decoy-related events)
        ▼
CSC PROD ACCOUNT (913511275171, us-west-2) — monitoring brain
┌──────────────────────────────────────────────────────────────┐
│  deception-global-event-bus                                  │
│  (resource policy: allows dev account to PutEvents)          │
│       │                                                      │
│  19 Detection Rules (one per scenario)                       │
│  - Second-layer scenario-specific pattern matching           │
│  - Target: Lambda via invoke role                            │
│       │                                                      │
│  deception-event-processor (Lambda, Python 3.11)             │
│  - Enriches CloudTrail detail                                │
│  - Whitelist check (suppresses Wiz scanner ARNs)             │
│  - Publishes formatted alert to SNS                          │
│       │                                                      │
│  deception-monitoring-alerts (SNS)                           │
│  → arhamjain@fico.com                                        │
│  → devanshunagpal@fico.com                                   │
└──────────────────────────────────────────────────────────────┘
```

## Folder Structure

```
Redo Monitoring Arch/
├── README.md                              ← this file
├── csc-prod/                              ← CSC Prod (913511275171)
│   ├── monitoring-brain.yaml              ← Stack 1: SNS + Lambda + EventBus + IAM
│   ├── detection-rules.yaml              ← Stack 2: 19 detection rules
│   └── deploy.sh                          ← deploys both + emails + bus permissions
└── dev-account-forwarding/                ← Dev account (046574264211)
    ├── forwarding-rule.yaml              ← 2 forwarding rules + 1 IAM role
    ├── deploy.sh                          ← deploys + verifies
    └── README.md                          ← dev-side docs
```

## Deployment Order

### Step 1: CSC Prod (deploy first)

```bash
cd csc-prod/
chmod +x deploy.sh
./deploy.sh
```

Deploys:
- `deception-monitoring-architecture` — brain (SNS, Lambda, EventBus, IAM)
- `deception-detection-rules` — 19 rules on global bus with Lambda targets
- Subscribes emails, grants dev account EventBus access

### Step 2: Dev Account (deploy second)

```bash
cd dev-account-forwarding/
chmod +x deploy.sh
./deploy.sh
```

Deploys:
- `deception-forwarding-rule` — 2 rules + 1 IAM role

## Two-Layer Filtering

| Layer | Location | Rules | Purpose |
|-------|----------|-------|---------|
| 1st | Dev account | 2 | Forward ONLY events touching decoy resources (cost reduction) |
| 2nd | CSC Prod | 19 | Scenario-specific pattern matching → Lambda (accuracy) |

### Dev account Rule 1 — STS lure roles
Forwards `AssumeRole` / `AssumeRoleWithSAML` ONLY on the 23 specific lure role ARNs.

### Dev account Rule 2 — Resource access
Forwards events from 13 AWS services ONLY when `requestParameters` matches a known decoy resource (bucket name, secret ID, table name, queue URL, etc.)

### CSC Prod — 19 detection rules
Each scenario has its own rule with the exact event pattern. When matched, invokes `deception-event-processor` Lambda which enriches and alerts via SNS.

## Cost Impact

| Approach | Monthly events forwarded | Est. cost |
|----------|--------------------------|-----------|
| Forward ALL CloudTrail | ~10M+ | ~$10+ |
| Old filtered (27 event names) | ~200K-500K | ~$0.50 |
| Current (decoy-specific resources) | ~1K-5K | <$0.01 |

The current approach forwards virtually nothing unless someone actually touches a decoy.

## Stacks Summary

| Stack | Account | What |
|-------|---------|------|
| `deception-monitoring-architecture` | 913511275171 | SNS, Lambda, EventBus, 2 IAM roles |
| `deception-detection-rules` | 913511275171 | 19 EventBridge rules → Lambda |
| `deception-forwarding-rule` | 046574264211 | 2 EventBridge rules + 1 IAM role → central bus |

## Adding a New Scenario

1. Add the lure role ARN to Rule 1 in `dev-account-forwarding/forwarding-rule.yaml`
2. Add decoy resource names to Rule 2's `$or` block
3. Add a new detection rule in `csc-prod/detection-rules.yaml`
4. Redeploy both stacks

## Tags

All resources: `Project: deception-monitoring`, `ManagedBy: cloudformation`
