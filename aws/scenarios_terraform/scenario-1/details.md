# scenario-1

Description: This deception scenario deploys a realistic-looking IAM role and S3 bucket containing a fake Terraform state file with expired placeholder credentials.

**Resources Deployed:**
- `infra-s3-data-readonly-role` (aws_iam_role)
- `infra-s3-data-readonly-policy` (aws_iam_policy)
- `infra-terraform-state-${var.account_id}` (aws_s3_bucket)
