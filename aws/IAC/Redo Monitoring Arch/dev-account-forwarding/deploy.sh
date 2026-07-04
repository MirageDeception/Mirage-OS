#!/bin/bash
# ==============================================================================
# deploy.sh — Dev Account Forwarding Rules (Consolidated 2-Rule Approach)
# Run with dev account credentials (where decoys are deployed)
# ==============================================================================

set -euo pipefail

STACK_NAME="deception-forwarding-rule"
REGION="us-west-2"
TEMPLATE_FILE="forwarding-rule.yaml"
CENTRAL_BUS_ARN="arn:aws:events:us-west-2:913511275171:event-bus/deception-global-event-bus"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Dev Account — Decoy Forwarding Rules      ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "  Account: ${ACCOUNT_ID}"
echo -e "  Region:  ${REGION}"
echo -e "  Target:  ${CENTRAL_BUS_ARN}"
echo ""

if [[ "${ACCOUNT_ID}" == "913511275171" ]]; then
  echo -e "${RED}  ERROR: This should NOT run in CSC Prod.${NC}"
  echo -e "${RED}  Run this in the dev account where decoys are deployed.${NC}"
  exit 1
fi

# --------------------------------------------------------------------------
# STEP 1: Validate
# --------------------------------------------------------------------------
echo -e "${YELLOW}[1/3] Validating template...${NC}"
aws cloudformation validate-template \
  --template-body "file://${TEMPLATE_FILE}" \
  --region "${REGION}" > /dev/null 2>&1
echo -e "${GREEN}  ✓ Template valid${NC}"
echo ""

# --------------------------------------------------------------------------
# STEP 2: Deploy
# --------------------------------------------------------------------------
echo -e "${YELLOW}[2/3] Deploying stack: ${STACK_NAME}...${NC}"
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    CentralEventBusArn="${CENTRAL_BUS_ARN}" \
    DevAccountId="${ACCOUNT_ID}" \
  --tags Project=deception-monitoring ManagedBy=cloudformation \
  --no-fail-on-empty-changeset
echo -e "${GREEN}  ✓ Stack deployed (2 forwarding rules + 1 IAM role)${NC}"
echo ""

# --------------------------------------------------------------------------
# STEP 3: Verify
# --------------------------------------------------------------------------
echo -e "${YELLOW}[3/3] Verifying...${NC}"

echo ""
echo -e "  Rules on default bus:"
aws events list-rules \
  --region "${REGION}" \
  --name-prefix "deception-fwd-" \
  --query "Rules[].{Name: Name, State: State}" \
  --output table

echo ""
aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs" \
  --output table

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Done                                      ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e "  ${YELLOW}Pre-requisite:${NC} CSC Prod must allow this account to"
echo -e "  forward events. Run this in CSC Prod (if not done already):"
echo ""
echo -e "  aws events put-permission \\"
echo -e "    --event-bus-name deception-global-event-bus \\"
echo -e "    --action events:PutEvents \\"
echo -e "    --principal ${ACCOUNT_ID} \\"
echo -e "    --statement-id \"AllowAccount-${ACCOUNT_ID}\" \\"
echo -e "    --region us-west-2"
echo ""
