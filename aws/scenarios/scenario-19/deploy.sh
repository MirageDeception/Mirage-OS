#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 21 (CloudFormation Stack Outputs Lure)
#
# This script:
#   1. Deploys the CloudFormation stack with exposed secrets in outputs
#   2. The stack creates minimal resources (SSM parameters) but the lure
#      is in the stack outputs and cross-stack exports
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and SSM parameters
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
STACK_NAME="prod-core-infrastructure"
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
warn "Stack name is 'prod-core-infrastructure' (looks like a real production stack)"
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
# Verify outputs are exposed
# ---------------------------------------------------------------
info "Verifying stack outputs are visible..."
OUTPUT_COUNT=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "length(Stacks[0].Outputs)" \
  --output text \
  --region "${REGION}")
ok "Stack has ${OUTPUT_COUNT} outputs exposed (including credentials)"

info "Verifying cross-stack exports..."
EXPORT_COUNT=$(aws cloudformation list-exports \
  --query "length(Exports[?starts_with(Name, 'prod-')])" \
  --output text \
  --region "${REGION}")
ok "Found ${EXPORT_COUNT} cross-stack exports with 'prod-' prefix"

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 21 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Role     : cfn-audit-readonly-role (discovery)"
echo "  SSM      :"
echo "    - /prod/core-infra/endpoints"
echo "    - /prod/core-infra/secrets-ref"
echo ""
echo "  Exposed Outputs (the lure):"
echo "    - DatabaseEndpoint, DatabasePassword"
echo "    - ApiGatewayUrl, ApiKey"
echo "    - RedisEndpoint, RedisAuthToken"
echo "    - AdminDashboardUrl"
echo ""
echo "  Cross-Stack Exports:"
echo "    - prod-database-endpoint"
echo "    - prod-api-gateway-url"
echo "    - prod-redis-endpoint"
echo "    - prod-vpc-id"
echo "    - prod-private-subnet-ids"
echo "    - prod-db-security-group-id"
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. All resources are live."
