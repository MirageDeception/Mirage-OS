# Cloud Deception — Dev Account Forwarding

Deployed in each AWS account where deception decoys exist. Forwards only events that touch specific decoy resources to the central `deception-global-event-bus` in CSC Prod.

## What Gets Deployed

| Resource | Name | Purpose |
|----------|------|---------|
| IAM Role | `deception-eventbridge-forwarding-role` | Allows EventBridge to PutEvents cross-account |
| EventBridge Rule 1 | `deception-fwd-sts-lure-roles` | Forwards AssumeRole on 23 lure role ARNs |
| EventBridge Rule 2 | `deception-fwd-resource-access` | Forwards events on decoy resources (S3, Secrets, SSM, DynamoDB, etc.) |

## Trust Policy (Least Privilege)

The IAM role's trust policy is scoped to:
- **Service**: `events.amazonaws.com` only
- **Account**: Only this dev account (`aws:SourceAccount`)
- **Rules**: Only rules matching `deception-fwd-*` (`ArnLike`)

No other rule in this account can reuse this forwarding role.

## Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

## Pre-requisite

The central event bus in CSC Prod must allow this account to PutEvents. Run this in CSC Prod:

```bash
aws events put-permission \
  --event-bus-name deception-global-event-bus \
  --action events:PutEvents \
  --principal 046574264211 \
  --statement-id "AllowAccount-046574264211" \
  --region us-west-2
```

(The CSC Prod deploy.sh handles this automatically)

## What Gets Forwarded

### Rule 1 — STS (23 lure role ARNs)
Only forwards AssumeRole/AssumeRoleWithSAML when the target is one of the deception lure roles.

### Rule 2 — All other services ($or matching)
Only forwards events where `requestParameters` matches a specific decoy resource:

| Service | Decoy Resources |
|---------|----------------|
| S3 | `infra-terraform-state-*`, `devops-deploy-keys-*`, `prod-data-sync-artifacts-*`, `compliance-audit-reports-*` |
| Secrets Manager | `prod/payment-gateway/*`, `prod/internal-api/service-accounts*`, `prod/data-sync/*`, `prod/compliance/*` |
| SSM | `/prod/database/*`, `/prod/ci-cd/*`, `/prod/monitoring/*`, `/prod/vpn/*`, `/prod/kubernetes/*`, `/prod/data-sync/*`, `/prod/compliance/*`, `/prod/auth/*`, `/prod/data/*`, `/prod/admin/*`, `/prod/db/*` |
| ECR | `prod-payment-service` |
| Lambda | `prod-data-sync-processor`, `prod-compliance-report-generator`, `prod-user-data-enrichment` |
| DynamoDB | `prod-customer-profiles`, `prod-active-sessions`, `prod-enriched-user-profiles` |
| SQS | `*prod-payment-events.fifo`, `*prod-payment-events-dlq.fifo` |
| SNS | `*:prod-alerts-critical` |
| CloudWatch Logs | `/prod/payment-service/application` |
| KMS | `alias/prod-customer-data-encryption*` |
| IAM | `*:saml-provider/ProdOktaSSO` |
| CloudFormation | `prod-core-infrastructure*` |
