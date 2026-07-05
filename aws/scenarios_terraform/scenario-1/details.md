# Scenario 1 Details

This deception scenario deploys a realistic-looking IAM role and S3 bucket containing a fake Terraform state file with expired placeholder credentials.

## Resources Created
- **IAM Role** (`infra-s3-data-readonly-role`): Appears as a privileged data-access role with read-only access to infrastructure S3 data stores.
- **S3 Bucket** (`infra-terraform-state-<account-id>`): Simulates a fake Terraform state backend with versioning, encryption, and public access blocks.
- **S3 Bucket Policy**: Allows root read access and denies insecure transport.
