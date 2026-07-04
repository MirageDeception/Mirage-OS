#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 19 and seed DynamoDB with enriched user PII
#
# This script:
#   1. Deploys the CloudFormation stack (Lambda + DynamoDB + IAM roles)
#   2. Seeds the DynamoDB table with fake enriched user records
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, Lambda functions, and DynamoDB tables
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
STACK_NAME="deception-scenario-19"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
TABLE_NAME="prod-enriched-user-profiles"

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
# Seed DynamoDB: enriched user profiles
# ---------------------------------------------------------------
info "Seeding DynamoDB table: ${TABLE_NAME} ..."

# Read the JSON array and write each item individually
RECORD_COUNT=$(jq length fake-data/enriched-users.json)
info "Loading ${RECORD_COUNT} enriched user records..."

for i in $(seq 0 $((RECORD_COUNT - 1))); do
  ITEM=$(jq -c ".[$i]" fake-data/enriched-users.json)
  aws dynamodb put-item \
    --table-name "${TABLE_NAME}" \
    --item "${ITEM}" \
    --region "${REGION}"
done

ok "DynamoDB table seeded with ${RECORD_COUNT} records."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 19 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Lambda   : prod-user-data-enrichment"
echo "  Roles    :"
echo "    - etl-ops-readonly-role (discovery)"
echo "    - prod-user-enrichment-exec-role (execution)"
echo "  DynamoDB : ${TABLE_NAME} (${RECORD_COUNT} records)"
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. All resources are live."
