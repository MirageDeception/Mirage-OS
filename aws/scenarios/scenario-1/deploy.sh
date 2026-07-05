#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 1 and seed the lure bucket
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, S3 buckets, and bucket policies
#
set -euo pipefail

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-1"
TEMPLATE_FILE="template.yaml"
FAKE_STATE_FILE="fake-data/terraform.tfstate"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID automatically
# ---------------------------------------------------------------
echo "[*] Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "[+] Account ID: ${ACCOUNT_ID}"

# Derived bucket name (must match the template)
BUCKET_NAME="infra-terraform-state-${ACCOUNT_ID}"

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
# Wait for the stack to reach a stable state
# ---------------------------------------------------------------
echo "[*] Waiting for stack to stabilize..."
aws cloudformation wait stack-create-complete \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" 2>/dev/null || true
# The wait may fail if the stack already existed (update path),
# but deploy --no-fail-on-empty-changeset handles that gracefully.

# ---------------------------------------------------------------
# Upload the fake Terraform state file into the lure bucket
# ---------------------------------------------------------------
echo "[*] Uploading fake Terraform state to s3://${BUCKET_NAME}/env/production/terraform.tfstate ..."
aws s3 cp "${FAKE_STATE_FILE}" \
  "s3://${BUCKET_NAME}/env/production/terraform.tfstate" \
  --region "${REGION}"

echo "[+] Fake state file uploaded."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "============================================="
echo "  Deception Scenario 1 — Deployed"
echo "============================================="
echo "  Stack   : ${STACK_NAME}"
echo "  Region  : ${REGION}"
echo "  Bucket  : ${BUCKET_NAME}"
echo "  Role    : infra-s3-data-readonly-role"
echo "  State   : s3://${BUCKET_NAME}/env/production/terraform.tfstate"
echo "============================================="
echo ""
echo "[*] Done. All resources are live."
