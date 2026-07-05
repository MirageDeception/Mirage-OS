#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 12 and seed DynamoDB with fake session records
#
# This script:
#   1. Deploys the CloudFormation stack (IAM role + DynamoDB table with TTL)
#   2. Seeds the DynamoDB table with fake active session records containing JWTs
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and DynamoDB tables
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
STACK_NAME="deception-scenario-12"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
TABLE_NAME="prod-active-sessions"
RECORDS_FILE="fake-data/session-records.json"

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
# Seed DynamoDB: fake session records
# ---------------------------------------------------------------
info "Seeding DynamoDB table: ${TABLE_NAME} ..."

RECORD_COUNT=$(jq length "${RECORDS_FILE}")
CURRENT=0

for row in $(jq -c '.[]' "${RECORDS_FILE}"); do
  CURRENT=$((CURRENT + 1))
  SESSION_ID=$(echo "$row" | jq -r '.session_id.S')
  USER_ID=$(echo "$row" | jq -r '.user_id.S')
  info "  Inserting session ${CURRENT}/${RECORD_COUNT}: ${SESSION_ID} (${USER_ID})"

  aws dynamodb put-item \
    --table-name "${TABLE_NAME}" \
    --item "$row" \
    --region "${REGION}"
done

ok "Seeded ${RECORD_COUNT} session records."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 12 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Role     : session-store-readonly-role"
echo "  Table    : ${TABLE_NAME}"
echo "  Records  : ${RECORD_COUNT} session records seeded"
echo "  TTL      : expires_at (future timestamps)"
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. All resources are live."
