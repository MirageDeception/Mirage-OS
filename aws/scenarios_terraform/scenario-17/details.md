# scenario-17

Description: Data Pipeline with PII Table. A Lambda function with environment variable API keys and a DynamoDB table seeded with enriched user PII records. Discovery role: etl-ops-readonly-role.

**Resources Deployed:**
- `etl-ops-readonly-role` (aws_iam_role)
- `etl-ops-readonly-policy` (aws_iam_policy)
- `prod-user-enrichment-exec-role` (aws_iam_role)
- `prod-user-enrichment-exec-policy` (aws_iam_policy)
- `prod-enriched-user-profiles` (aws_dynamodb_table)
- `prod-user-data-enrichment` (aws_lambda_function)
