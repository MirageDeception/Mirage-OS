# scenario-13

Description: CloudWatch Logs lure with accidentally logged credentials in a payment service log group. Uses a discovery role for read-only access.

**Resources Deployed:**
- `log-analysis-readonly-role` (aws_iam_role)
- `log-analysis-readonly-policy` (aws_iam_policy)
- `/prod/payment-service/application` (aws_cloudwatch_log_group)
