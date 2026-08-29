# scenario-6

Description: Deception Scenario 6 - Lambda Blueprint. A Lambda function with hardcoded secrets in environment variables. Discovery role grants read-only access to Lambda configuration. Optionally includes S3, Secrets Manager, and SSM as downstream pivot targets for the execution role. This scenario serves as a base that other scenarios (7, 8) can link to.

**Resources Deployed:**
- `lambda-ops-readonly-role` (aws_iam_role)
- `lambda-ops-readonly-policy` (aws_iam_role_policy)
- `prod-data-sync-exec-role` (aws_iam_role)
- `prod-data-sync-exec-base-policy` (aws_iam_role_policy)
- `prod-data-sync-exec-s3-policy` (aws_iam_role_policy)
- `prod-data-sync-exec-sm-policy` (aws_iam_role_policy)
- `prod-data-sync-exec-ssm-policy` (aws_iam_role_policy)
- `prod-data-sync-processor` (aws_lambda_function)
- `prod-data-sync-artifacts-${var.account_id}` (aws_s3_bucket)
- `prod/data-sync/api-credentials` (aws_secretsmanager_secret)
- `/prod/data-sync/config` (aws_ssm_parameter)
