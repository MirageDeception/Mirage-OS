# scenario-4

Description: This deception scenario deploys a lure IAM role with an S3 SSH key that leads to an EC2 bastion instance seeded with sensitive files. The instance is deployed in a stopped state, requiring the attacker to modify the security group and start it.

**Resources Deployed:**
- `prod-bastion-sg` (aws_security_group)
- `devops-s3-deploy-role` (aws_iam_role)
- `devops-s3-deploy-policy` (aws_iam_policy)
- `devops-deploy-keys-${var.account_id}` (aws_s3_bucket)
