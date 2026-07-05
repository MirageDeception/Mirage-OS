#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 7 (Lambda Code Injection)
#
# Adds InvokeFunction + UpdateFunctionCode permissions, enabling an attacker
# to inject code and steal the Lambda execution role's credentials.
#
# Can either:
#   A) Link to Scenario 6 (adds permissions to existing role/function)
#   B) Deploy standalone (creates its own Lambda + roles)
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
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-7"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID
# ---------------------------------------------------------------
info "Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ok "Account ID: ${ACCOUNT_ID}"

# ---------------------------------------------------------------
# Check if Scenario 6 exists
# ---------------------------------------------------------------
SCENARIO6_EXISTS="false"
SCENARIO6_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name "deception-scenario-6" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='LambdaFunctionName'].OutputValue" \
  --output text 2>/dev/null || echo "")

if [ -n "${SCENARIO6_FUNCTION}" ] && [ "${SCENARIO6_FUNCTION}" != "None" ]; then
  SCENARIO6_EXISTS="true"
fi

# ---------------------------------------------------------------
# Ask: Link to Scenario 6 or standalone?
# ---------------------------------------------------------------
echo ""
echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}  Scenario 7 — Lambda Code Injection${NC}"
echo -e "${CYAN}=============================================${NC}"
echo ""

LINK_TO_6="false"
if [ "${SCENARIO6_EXISTS}" = "true" ]; then
  echo -e "  ${GREEN}Scenario 6 detected:${NC} Lambda function '${SCENARIO6_FUNCTION}'"
  echo ""
  echo "  Options:"
  echo "    L) Link to Scenario 6 — adds InvokeFunction + UpdateFunctionCode"
  echo "       to the existing discovery role (no new Lambda created)"
  echo "    S) Standalone — creates a separate Lambda + roles"
  echo ""
  read -rp "  Link to Scenario 6 or Standalone? [L/s]: " LINK_CHOICE
  LINK_CHOICE=${LINK_CHOICE:-L}
  if [ "${LINK_CHOICE}" = "L" ] || [ "${LINK_CHOICE}" = "l" ]; then
    LINK_TO_6="true"
  fi
else
  warn "Scenario 6 not deployed. Deploying standalone."
  echo ""
fi

# ---------------------------------------------------------------
# Show cost estimate
# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}--- Cost Estimate ---${NC}"
if [ "${LINK_TO_6}" = "true" ]; then
  echo "  Additional IAM policy only:   \$0.00"
  echo "  (Lambda + resources from Scenario 6)"
  echo -e "  ${GREEN}Total additional: \$0.00/mo${NC}"
else
  echo "  Lambda (never invoked):       \$0.00"
  echo "  SSM Standard (1 param):       \$0.00"
  echo "  IAM resources:                \$0.00"
  echo -e "  ${GREEN}Total: \$0.00/mo${NC}"
fi
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
      LinkToScenario6="${LINK_TO_6}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

ok "Stack deployed successfully."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 7 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
if [ "${LINK_TO_6}" = "true" ]; then
  echo "  Mode     : Linked to Scenario 6"
  echo "  Function : ${SCENARIO6_FUNCTION} (from scenario-6)"
  echo "  Added    : InvokeFunction + UpdateFunctionCode to discovery role"
  echo "  Attack   : Inject code → invoke → steal exec role creds"
else
  echo "  Mode     : Standalone"
  echo "  Function : prod-data-inject-processor"
  echo "  Role     : lambda-inject-readonly-role"
  echo "  Attack   : Inject code → invoke → steal exec role creds"
fi
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. Run abuse.sh to simulate the attack."
