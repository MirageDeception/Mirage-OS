#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 2 and seed Secrets Manager with fake data
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and Secrets Manager secrets
#
set -euo pipefail

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-2"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID automatically
# ---------------------------------------------------------------
echo "[*] Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "[+] Account ID: ${ACCOUNT_ID}"

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
# Wait for stack to stabilize
# ---------------------------------------------------------------
echo "[*] Waiting for stack to stabilize..."
aws cloudformation wait stack-create-complete \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" 2>/dev/null || true

# ---------------------------------------------------------------
# Seed Secret 1: Stripe keys
# ---------------------------------------------------------------
echo "[*] Updating secret: prod/payment-gateway/stripe-keys ..."
aws secretsmanager put-secret-value \
  --secret-id "prod/payment-gateway/stripe-keys" \
  --secret-string file://fake-data/stripe-keys.json \
  --region "${REGION}"
echo "[+] Stripe keys secret seeded."

# ---------------------------------------------------------------
# Seed Secret 2: Braintree credentials
# ---------------------------------------------------------------
echo "[*] Updating secret: prod/payment-gateway/braintree-credentials ..."
aws secretsmanager put-secret-value \
  --secret-id "prod/payment-gateway/braintree-credentials" \
  --secret-string file://fake-data/braintree-credentials.json \
  --region "${REGION}"
echo "[+] Braintree credentials secret seeded."

# ---------------------------------------------------------------
# Seed Secret 3: Internal service accounts
# ---------------------------------------------------------------
echo "[*] Updating secret: prod/internal-api/service-accounts ..."
aws secretsmanager put-secret-value \
  --secret-id "prod/internal-api/service-accounts" \
  --secret-string file://fake-data/service-accounts.json \
  --region "${REGION}"
echo "[+] Service accounts secret seeded."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "============================================="
echo "  Deception Scenario 2 — Deployed"
echo "============================================="
echo "  Stack   : ${STACK_NAME}"
echo "  Region  : ${REGION}"
echo "  Role    : payment-secrets-readonly-role"
echo "  Secrets :"
echo "    - prod/payment-gateway/stripe-keys"
echo "    - prod/payment-gateway/braintree-credentials"
echo "    - prod/internal-api/service-accounts"
echo "============================================="
echo ""
echo "[*] Done. All resources are live."
