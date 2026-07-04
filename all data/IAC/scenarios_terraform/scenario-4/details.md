# Scenario 4 Details

This deception scenario deploys a lure IAM role with an S3 SSH key that leads to an EC2 bastion instance seeded with sensitive files. The instance is deployed in a stopped state, requiring the attacker to modify the security group and start it.

## Resources Created
- **IAM Role** (`devops-s3-deploy-role`): Has permissions to read a deployment keys bucket and start/modify the bastion instance.
- **S3 Bucket** (`devops-deploy-keys-<account-id>`): Simulates a deploy keys store.
- **EC2 Instance** (`prod-bastion-host`): A bastion instance seeded with sensitive files in its user data.
- **Security Group** (`prod-bastion-sg`): A security group for the bastion instance.
