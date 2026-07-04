#!/bin/bash
# ==============================================================================
# deploy.sh — Dev Account v2 Forwarding (deception-v2-* naming)
# Does NOT touch v1 resources. Run with dev account credentials.
# ==============================================================================

set -euo pipefail

STACK_NAME="deception-v2-forwarding"
REGION="us-west-2"
TEMPLATE_FILE="forwarding-rule.yaml"
CENTRAL_BUS_ARN="arn:aws:events:us-west-2:913511275171:event-bus/deception-v2-global-bus"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Dev Account v2 — Forwarding Rules         ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "  Account: ${ACCOUNT_ID}"
echo -e "  Region:  ${REGION}"
echo -e "  Target:  ${CENTRAL_BUS_ARN}"
echo -e "  Version: v2 (separate from v1)"
echo ""

if [[ "${ACCOUNT_ID}" == "913511275171" ]]; then
  echo -e "${RED}  ERROR: Do NOT run this in CSC Prod.${NC}"
  exit 1
fi

echo -e "${YELLOW}[1/3] Validating...${NC}"
aws cloudformation validate-template \
  --template-body "file://${TEMPLATE_FILE}" \
  --region "${REGION}" > /dev/null 2>&1
echo -e "${GREEN}  ✓ Valid${NC}"
echo ""

echo -e "${YELLOW}[2/3] Deploying: ${STACK_NAME}...${NC}"
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    CentralEventBusArn="${CENTRAL_BUS_ARN}" \
    DevAccountId="${ACCOUNT_ID}" \
  --tags Project=deception-monitoring ManagedBy=cloudformation Version=v2 \
  --no-fail-on-empty-changeset
echo -e "${GREEN}  ✓ Deployed (2 rules + 1 role)${NC}"
echo ""

echo -e "${YELLOW}[3/3] Verifying...${NC}"
aws events list-rules --region "${REGION}" --name-prefix "deception-v2-fwd-" \
  --query "Rules[].{Name: Name, State: State}" --output table
echo ""

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  v2 Dev Account Complete                   ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e "  ${YELLOW}Pre-req:${NC} CSC Prod must allow this account on v2 bus."
echo -e "  The CSC Prod deploy.sh handles this, or manually:"
echo ""
echo -e "  aws events put-permission \\"
echo -e "    --event-bus-name deception-v2-global-bus \\"
echo -e "    --action events:PutEvents \\"
echo -e "    --principal ${ACCOUNT_ID} \\"
echo -e "    --statement-id \"AllowAccount-${ACCOUNT_ID}\" \\"
echo -e "    --region us-west-2"
echo ""
