# Deception Scenario 14 - SNS Lure

**Description:**
Critical alerts topic and subscription endpoints. Contains an SNS topic and dummy subscriptions to endpoints that will be in a PendingConfirmation state. An IAM role granting read-only access to the SNS alerting infrastructure is provisioned for discovery.

**Resources Created:**
1. `alerts-readonly-role` (IAM Role) - Grants read-only access to SNS alerting infrastructure.
2. `alerts-readonly-policy` (IAM Policy) - Allows listing topics and reading attributes of the critical alerts topic.
3. `prod-alerts-critical` (SNS Topic) - Main topic encrypted with SSE. Policy restricts publishing to the account root.
4. SNS Subscriptions - HTTPS webhook and Email subscriptions (kept in `PendingConfirmation`).
