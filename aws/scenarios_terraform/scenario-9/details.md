# scenario-9

Description: Deception Scenario 11 - DynamoDB Lure: Customer Profiles + Active Sessions. Two DynamoDB tables seeded with fake PII and JWT session tokens. A single IAM role grants read-only access to both tables. Every scan or query generates CloudTrail events for detection.

**Resources Deployed:**
- `customer-data-readonly-role` (aws_iam_role)
- `customer-data-list-policy` (aws_iam_role_policy)
- `customer-profiles-readonly-policy` (aws_iam_role_policy)
- `active-sessions-readonly-policy` (aws_iam_role_policy)
- `prod-customer-profiles` (aws_dynamodb_table)
- `prod-active-sessions` (aws_dynamodb_table)
