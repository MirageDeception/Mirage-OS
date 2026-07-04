#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 11 (DynamoDB Customer Data Lure)
#
# Deploys one or two DynamoDB tables with a single read-only IAM role:
#   - prod-customer-profiles (fake PII)
#   - prod-active-sessions (fake JWTs)
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
set -euo pipefail

# ---------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-11"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID
# ---------------------------------------------------------------
info "Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ok "Account ID: ${ACCOUNT_ID}"

# ---------------------------------------------------------------
# Ask which tables to include
# ---------------------------------------------------------------
echo ""
echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}  Scenario 11 — DynamoDB Customer Data Lure${NC}"
echo -e "${CYAN}  Select which tables to deploy:${NC}"
echo -e "${CYAN}=============================================${NC}"
echo ""

read -rp "  Include Customer Profiles table (fake PII)? [Y/n]: " INCLUDE_PROFILES
INCLUDE_PROFILES=${INCLUDE_PROFILES:-Y}
if [ "${INCLUDE_PROFILES}" = "Y" ] || [ "${INCLUDE_PROFILES}" = "y" ]; then
  INCLUDE_PROFILES="true"
else
  INCLUDE_PROFILES="false"
fi

read -rp "  Include Active Sessions table (fake JWTs)? [Y/n]: " INCLUDE_SESSIONS
INCLUDE_SESSIONS=${INCLUDE_SESSIONS:-Y}
if [ "${INCLUDE_SESSIONS}" = "Y" ] || [ "${INCLUDE_SESSIONS}" = "y" ]; then
  INCLUDE_SESSIONS="true"
else
  INCLUDE_SESSIONS="false"
fi

# ---------------------------------------------------------------
# Show cost estimate
# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}--- Cost Estimate ---${NC}"
echo "  DynamoDB on-demand (no traffic): \$0.00"
echo "  SSE encryption (AWS-owned key):  \$0.00"
echo "  IAM resources:                   \$0.00"
echo -e "  ${GREEN}Total: \$0.00/mo${NC}"
echo ""

read -rp "  Deploy? [Y/n]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-Y}
if [ "${DEPLOY_CONFIRM}" != "Y" ] && [ "${DEPLOY_CONFIRM}" != "y" ]; then
  echo "Aborted."
  exit 0
fi

# ---------------------------------------------------------------
# Deploy the CloudFormation stack
# ---------------------------------------------------------------
info "Deploying CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides \
      AccountId="${ACCOUNT_ID}" \
      IncludeCustomerProfiles="${INCLUDE_PROFILES}" \
      IncludeActiveSessions="${INCLUDE_SESSIONS}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

ok "Stack deployed successfully."

# ---------------------------------------------------------------
# Seed DynamoDB tables
# ---------------------------------------------------------------
if [ "${INCLUDE_PROFILES}" = "true" ]; then
  info "Seeding prod-customer-profiles table..."
  ITEMS=$(cat fake-data/customer-records.json | jq -c '.[]')
  while IFS= read -r item; do
    aws dynamodb put-item \
      --table-name "prod-customer-profiles" \
      --item "${item}" \
      --region "${REGION}" 2>/dev/null
  done <<< "${ITEMS}"
  ok "Customer profiles seeded ($(echo "${ITEMS}" | wc -l) records)."
fi

if [ "${INCLUDE_SESSIONS}" = "true" ]; then
  info "Seeding prod-active-sessions table..."
  ITEMS=$(cat fake-data/session-records.json | jq -c '.[]')
  while IFS= read -r item; do
    aws dynamodb put-item \
      --table-name "prod-active-sessions" \
      --item "${item}" \
      --region "${REGION}" 2>/dev/null
  done <<< "${ITEMS}"
  ok "Active sessions seeded ($(echo "${ITEMS}" | wc -l) records)."
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 11 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Role     : customer-data-readonly-role"
echo "  Tables   :"
if [ "${INCLUDE_PROFILES}" = "true" ]; then
echo "    - prod-customer-profiles (12 PII records)"
fi
if [ "${INCLUDE_SESSIONS}" = "true" ]; then
echo "    - prod-active-sessions (9 JWT sessions)"
fi
echo "  Cost     : \$0.00/mo"
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. Run abuse.sh to simulate the attack."
