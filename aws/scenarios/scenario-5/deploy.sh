#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 5 (ECR lure)
#
# This script:
#   1. Deploys the CloudFormation stack (ECR repo + IAM role + instance profile)
#   2. Builds the Docker image from fake-data/docker/
#   3. Authenticates to ECR and pushes the image with two tags
#   4. Checks if scenario-4 is deployed — if so, attaches the instance profile
#      to the scenario-4 bastion instance
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Docker installed and running
#   - Sufficient IAM permissions for CloudFormation, ECR, IAM, EC2
#
set -euo pipefail

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-5"
SCENARIO4_STACK="deception-scenario-4"
TEMPLATE_FILE="template.yaml"
DOCKER_DIR="fake-data/docker"
REPO_NAME="prod-payment-service"
IMAGE_TAG_LATEST="latest"
IMAGE_TAG_VERSION="v2.14.3"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID
# ---------------------------------------------------------------
echo "[*] Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "[+] Account ID: ${ACCOUNT_ID}"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

# ---------------------------------------------------------------
# Deploy the CloudFormation stack
# ---------------------------------------------------------------
echo "[*] Deploying CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides AccountId="${ACCOUNT_ID}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

echo "[+] Stack deployed successfully."

# ---------------------------------------------------------------
# Build the Docker image
# ---------------------------------------------------------------
echo "[*] Building Docker image from ${DOCKER_DIR} ..."
docker build -t "${REPO_NAME}:${IMAGE_TAG_LATEST}" "${DOCKER_DIR}"
docker tag "${REPO_NAME}:${IMAGE_TAG_LATEST}" "${REPO_NAME}:${IMAGE_TAG_VERSION}"
echo "[+] Image built and tagged."

# ---------------------------------------------------------------
# Authenticate to ECR and push the image
# ---------------------------------------------------------------
echo "[*] Authenticating to ECR..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "[*] Pushing image: ${ECR_URI}:${IMAGE_TAG_LATEST} ..."
docker tag "${REPO_NAME}:${IMAGE_TAG_LATEST}" "${ECR_URI}:${IMAGE_TAG_LATEST}"
docker push "${ECR_URI}:${IMAGE_TAG_LATEST}"

echo "[*] Pushing image: ${ECR_URI}:${IMAGE_TAG_VERSION} ..."
docker tag "${REPO_NAME}:${IMAGE_TAG_VERSION}" "${ECR_URI}:${IMAGE_TAG_VERSION}"
docker push "${ECR_URI}:${IMAGE_TAG_VERSION}"

echo "[+] Images pushed to ECR."

# ---------------------------------------------------------------
# Check if scenario-4 is deployed and attach instance profile
# ---------------------------------------------------------------
echo "[*] Checking if scenario-4 stack (${SCENARIO4_STACK}) exists..."

INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name "${SCENARIO4_STACK}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" \
  --output text 2>/dev/null || echo "")

PROFILE_NAME=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceProfileName'].OutputValue" \
  --output text)

if [ -n "${INSTANCE_ID}" ] && [ "${INSTANCE_ID}" != "None" ]; then
  echo "[+] Scenario-4 found. Instance ID: ${INSTANCE_ID}"

  # Check if an instance profile is already associated
  EXISTING_ASSOC=$(aws ec2 describe-iam-instance-profile-associations \
    --filters "Name=instance-id,Values=${INSTANCE_ID}" \
    --region "${REGION}" \
    --query "IamInstanceProfileAssociations[0].AssociationId" \
    --output text 2>/dev/null || echo "None")

  if [ "${EXISTING_ASSOC}" != "None" ] && [ -n "${EXISTING_ASSOC}" ]; then
    echo "[*] Replacing existing instance profile association: ${EXISTING_ASSOC} ..."
    aws ec2 replace-iam-instance-profile-association \
      --association-id "${EXISTING_ASSOC}" \
      --iam-instance-profile Name="${PROFILE_NAME}" \
      --region "${REGION}"
  else
    echo "[*] Attaching instance profile to scenario-4 bastion..."
    aws ec2 associate-iam-instance-profile \
      --instance-id "${INSTANCE_ID}" \
      --iam-instance-profile Name="${PROFILE_NAME}" \
      --region "${REGION}"
  fi

  echo "[+] Instance profile attached to ${INSTANCE_ID}."
  echo "[+] Full attack chain active: S3 → EC2 → ECR"
else
  echo "[!] WARNING: Scenario-4 stack not found."
  echo "[!] ECR lure deployed standalone. Deploy scenario-4 first for the full chain."
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "============================================="
echo "  Deception Scenario 5 — Deployed"
echo "============================================="
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  ECR Repo : ${ECR_URI}"
echo "  Tags     : ${IMAGE_TAG_LATEST}, ${IMAGE_TAG_VERSION}"
echo "  Role     : prod-bastion-ecr-role"
echo "  Profile  : ${PROFILE_NAME}"
if [ -n "${INSTANCE_ID}" ] && [ "${INSTANCE_ID}" != "None" ]; then
echo "  Linked   : scenario-4 instance ${INSTANCE_ID}"
fi
echo "============================================="
echo ""
echo "[*] Done. All resources are live."
