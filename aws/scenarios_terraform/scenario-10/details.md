# scenario-10

Description: Fake Active Sessions Table. A DynamoDB table seeded with realistic session records containing JWT tokens and an IAM role granting read-only access. Every scan or query generates CloudTrail events for detection.

**Resources Deployed:**
- `session-store-readonly-role` (aws_iam_role)
- `session-store-readonly-policy` (aws_iam_policy)
- `prod-active-sessions` (aws_dynamodb_table)
