# Scenario 5 Details

This deception scenario deploys an ECR lure repository designed to hold a container image with fake PII, credentials, and an ASIA token placeholder. It also includes an instance profile that can be optionally linked to the Scenario 4 bastion.

## Resources Created
- **IAM Role & Instance Profile** (`prod-bastion-ecr-role`, `prod-bastion-ecr-profile`): Provides ECR read access for a bastion host.
- **ECR Repository** (`prod-payment-service`): A container registry repository that simulates a payment service.
- **ECR Repository Policy**: Grants the account root access to pull images.
