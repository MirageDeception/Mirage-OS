# Scenario 7 — Lambda Code Injection: Steal Execution Role Credentials

## Deception Story

An attacker discovers they can not only read a Lambda function's configuration
but also update its code and invoke it. They inject a credential-exfiltration
payload, invoke the function, and receive the execution role's temporary ASIA
session credentials — giving them access to S3, Secrets Manager, and SSM.

## Attack Path

```
Attacker
  │
  ├─► Assumes discovery role (lambda-ops-readonly-role or lambda-inject-readonly-role)
  │
  ├─► Reads Lambda config → extracts env var secrets (DB creds, Stripe key)
  │
  ├─► Notices execution role ARN → knows what it can access
  │
  ├─► UpdateFunctionCode → injects credential exfiltration payload ⚠️ CRITICAL SIGNAL
  │
  ├─► InvokeFunction → payload returns execution role ASIA credentials ⚠️ CRITICAL SIGNAL
  │
  ├─► Uses stolen credentials to access:
  │     ├─► S3 bucket (pipeline artifacts)
  │     ├─► Secrets Manager (API credentials)
  │     └─► SSM parameter (pipeline config)
  │
  └─► Restores original code (cleanup attempt)
```

## Deployment Modes

| Mode | Description |
|------|-------------|
| **Linked** (recommended) | Adds `InvokeFunction` + `UpdateFunctionCode` to Scenario 6's existing discovery role. No new Lambda created. |
| **Standalone** | Creates its own Lambda function + roles. Independent of Scenario 6. |

## Detection Signals

| Signal | CloudTrail Event | Confidence |
|--------|-----------------|------------|
| Code injection | UpdateFunctionCode | **Critical** |
| Function invoke | Invoke | **Critical** |
| Role assumption | AssumeRole | High |
| Config read | GetFunctionConfiguration | High |

## Cost

| Component | Monthly |
|-----------|---------|
| IAM policy (linked mode) | $0.00 |
| Lambda + IAM (standalone mode) | $0.00 |
| **Total** | **$0.00** |

## Deployment

```bash
chmod +x deploy.sh
./deploy.sh
```

The script will ask whether to link to Scenario 6 or deploy standalone.
