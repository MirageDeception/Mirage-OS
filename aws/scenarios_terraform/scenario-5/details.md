# scenario-5

Description: This deception scenario deploys an ECR lure repository designed to hold a container image with fake PII, credentials, and an ASIA token placeholder. It also includes an instance profile that can be optionally linked to the Scenario 4 bastion.

**Resources Deployed:**
- `prod-bastion-ecr-role` (aws_iam_role)
- `prod-bastion-ecr-readonly-policy` (aws_iam_policy)
- `prod-bastion-ecr-profile` (aws_iam_instance_profile)
- `prod-payment-service` (aws_ecr_repository)
