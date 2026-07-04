# Scenario 14 — SNS Lure: Critical Alerts Topic with Subscription Endpoints

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`alerts-readonly-role` — assumable by any principal in the account. The role
grants read-only access to SNS topics and subscriptions.

The attacker lists SNS topics and finds `prod-alerts-critical`. Reading its
attributes reveals the topic policy, encryption configuration, and subscription
count. Listing subscriptions exposes internal infrastructure endpoints:

- An HTTPS webhook at `hooks.prod.internal.corp/alerts/critical`
- An email address `oncall-sre@acme-corp.com`

Both subscriptions remain in PendingConfirmation state and will never deliver
messages. The realistic naming and endpoint formats are designed to lure the
attacker into attempting to publish messages or subscribe their own endpoint —
triggering detection alerts.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: alerts-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains sns:ListTopics, sns:GetTopicAttributes,
  │                    sns:ListSubscriptionsByTopic
  │
  ├─► Lists SNS topics → finds prod-alerts-critical
  │
  ├─► Gets topic attributes → sees topic policy, encryption, subscription count
  │
  ├─► Lists subscriptions → discovers endpoints:
  │     ├─► HTTPS webhook: https://hooks.prod.internal.corp/alerts/critical
  │     └─► Email: oncall-sre@acme-corp.com
  │
  └─► Attacker attempts to publish or subscribe → triggers alerts
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `alerts-readonly-role` |
| Alerts Topic | SNS Topic | `prod-alerts-critical` |
| HTTPS Subscription | SNS Subscription | `https://hooks.prod.internal.corp/alerts/critical` |
| Email Subscription | SNS Subscription | `oncall-sre@acme-corp.com` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — SNS topic + subscriptions + IAM role |
| `deploy.sh` | One-command deploy script — creates the stack |
| `abuse.sh` | Simulates the attacker abuse chain step by step |

## Security Best Practices Applied

- SNS topic: SSE encryption using `alias/aws/sns` KMS key
- Topic policy: publish restricted to account root principal only, external publish denied
- IAM discovery role: trust policy scoped to account root principal (not public)
- Discovery role permissions scoped to specific topic ARN (except ListTopics)
- Subscriptions stay PendingConfirmation — no real message delivery
- No cross-account access

## Cost

$0.00/month — no traffic, no message delivery.

## Deployment

### Quick deploy (recommended)

```bash
chmod +x deploy.sh
./deploy.sh
```

Override region:

```bash
AWS_DEFAULT_REGION=eu-west-1 ./deploy.sh
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-14 --region us-west-2
```
