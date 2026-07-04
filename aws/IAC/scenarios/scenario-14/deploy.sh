#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 16 (KMS Customer Data Encryption Key)
#
# This script:
#   1. Deploys the CloudFormation stack (KMS key + alias + IAM role)
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and KMS keys
#
set -euo pipefail

# ---------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-16"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID automatically
# ---------------------------------------------------------------
info "Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ok "Account ID: ${ACCOUNT_ID}"

# ---------------------------------------------------------------
# Deploy the CloudFormation stack
# ---------------------------------------------------------------
info "Deploying CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides AccountId="${ACCOUNT_ID}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

ok "Stack deployed successfully."

# ---------------------------------------------------------------
# Wait for stack to stabilize
# ---------------------------------------------------------------
info "Waiting for stack to stabilize..."
aws cloudformation wait stack-create-complete \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" 2>/dev/null || true

# ---------------------------------------------------------------
# Verify KMS key and alias
# ---------------------------------------------------------------
info "Verifying KMS key..."
KEY_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='KmsKeyId'].OutputValue" \
  --output text)

KEY_STATE=$(aws kms describe-key \
  --key-id "${KEY_ID}" \
  --region "${REGION}" \
  --query "KeyMetadata.KeyState" \
  --output text)

ok "KMS Key ID: ${KEY_ID}"
ok "Key State: ${KEY_STATE}"

info "Verifying alias..."
ALIAS_TARGET=$(aws kms list-aliases \
  --region "${REGION}" \
  --query "Aliases[?AliasName=='alias/prod-customer-data-encryption'].TargetKeyId" \
  --output text)
ok "Alias alias/prod-customer-data-encryption → ${ALIAS_TARGET}"

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 16 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  KMS Key  : ${KEY_ID}"
echo "  Alias    : alias/prod-customer-data-encryption"
echo "  Role     : kms-audit-readonly-role (discovery)"
echo -e "${GREEN}=============================================${NC}"
echo ""
warn "Lure role can describe/list the key but decrypt is explicitly denied."
warn "Cost: ~\$1.00/month for the KMS key."
echo ""
ok "Done. All resources are live."
