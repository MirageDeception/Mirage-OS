# Scenario 14 — SNS Lure: Critical Alerts Topic with Subscription Endpoints

## Prompt

Create a deception scenario called `scenario-14` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: alerts-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► sns:ListTopics → finds prod-alerts-critical
  │
  ├─► sns:GetTopicAttributes → sees topic policy, subscription count
  │
  ├─► sns:ListSubscriptionsByTopic → discovers endpoints:
  │     ├─► HTTPS webhook: https://hooks.prod.internal.corp/alerts
  │     ├─► Email: oncall-sre@acme-corp.com
  │     └─► Lambda: arn:aws:lambda:...:prod-alert-handler
  │
  ├─► Attempts to sns:Publish to the topic → triggers detection
  │   (or attempts to subscribe their own endpoint)
  │
  └─► Extracted endpoints reveal internal infrastructure
```

### Lure Resources

- **IAM Role**: Named `alerts-readonly-role`
  - `sns:ListTopics`
  - `sns:GetTopicAttributes`, `sns:ListSubscriptionsByTopic` — scoped to lure topic
  - Trust: account root principal

- **SNS Topic**: Named `prod-alerts-critical`
  - Encryption: SSE (aws/sns KMS key)
  - Topic policy allows publish from account root only
  - Tags: `Environment=production`, `Project=sre-platform`, `Severity=critical`

- **SNS Subscriptions** (pending confirmation — won't actually deliver):
  - HTTPS endpoint: `https://hooks.prod.internal.corp/alerts/critical`
  - Email: `oncall-sre@acme-corp.com` (pending confirmation)

### Additional Requirements

- [ ] Cost: $0.00/month (no traffic)
- [ ] Subscriptions stay in PendingConfirmation state (no real delivery)
- [ ] Include `deploy.sh`, `README.md`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-14/
├── template.yaml
├── deploy.sh
└── README.md
```
