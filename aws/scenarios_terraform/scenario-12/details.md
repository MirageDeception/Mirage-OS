# scenario-12

Description: Critical alerts topic and subscription endpoints. Contains an SNS topic and dummy subscriptions to endpoints that will be in a PendingConfirmation state. An IAM role granting read-only access to the SNS alerting infrastructure is provisioned for discovery.

**Resources Deployed:**
- `alerts-readonly-role` (aws_iam_role)
- `alerts-readonly-policy` (aws_iam_policy)
- `prod-alerts-critical` (aws_sns_topic)
