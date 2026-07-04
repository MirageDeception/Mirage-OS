# Deception Scenario 15 - CloudWatch Logs Lure

**Description:**
CloudWatch Logs lure with accidentally logged credentials in a payment service log group. Uses a discovery role for read-only access.

**Resources Created:**
1. `log-analysis-readonly-role` (IAM Role) - Grants read-only access to CloudWatch Logs for debugging and analysis.
2. `log-analysis-readonly-policy` (IAM Policy) - Allows describing log groups, streams, and retrieving log events scoped to the `/prod/payment-service/application` log group.
3. `/prod/payment-service/application` (CloudWatch Log Group) - Log group with a 30-day retention period.
