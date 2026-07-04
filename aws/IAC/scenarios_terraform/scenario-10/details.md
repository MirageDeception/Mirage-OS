# Deception Scenario 12 - DynamoDB Lure

**Description:**
Fake Active Sessions Table. A DynamoDB table seeded with realistic session records containing JWT tokens and an IAM role granting read-only access. Every scan or query generates CloudTrail events for detection.

**Resources Created:**
1. `session-store-readonly-role` (IAM Role) - Grants read-only access scoped to the lure table.
2. `session-store-readonly-policy` (IAM Policy) - Allows DynamoDB list tables and read operations on the active sessions table.
3. `prod-active-sessions` (DynamoDB Table) - On-demand billing, partition key `session_id`, sort key `user_id`. Has TTL enabled on `expires_at` to look like live sessions.
