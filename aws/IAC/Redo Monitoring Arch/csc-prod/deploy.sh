#!/bin/bash
# ==============================================================================
# deploy.sh — CSC Prod: Monitoring Brain + Detection Rules
# Run with CSC Prod credentials (account 913511275171, us-west-2)
#
# Deploys two stacks:
#   1. deception-monitoring-architecture — SNS, Lambda, EventBus, IAM roles
#   2. deception-detection-rules — 19 scenario rules on the global event bus
# ==============================================================================

set -euo pipefail

REGION="us-west-2"
BRAIN_STACK="deception-monitoring-architecture"
RULES_STACK="deception-detection-rules"
BRAIN_TEMPLATE="monitoring-brain.yaml"
RULES_TEMPLATE="detection-rules.yaml"

DEFAULT_EMAILS=(
  "arhamjain@fico.com"
  "devanshunagpal@fico.com"
)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  CSC Prod — Monitoring Brain + Detection   ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "  Account: ${ACCOUNT_ID}"
echo -e "  Region:  ${REGION}"
echo ""

if [[ "${ACCOUNT_ID}" != "913511275171" ]]; then
  echo -e "${RED}  ERROR: This must be run with CSC Prod credentials (913511275171)${NC}"
  echo -e "${RED}  Current account: ${ACCOUNT_ID}${NC}"
  exit 1
fi

# --------------------------------------------------------------------------
# STEP 1: Deploy Monitoring Brain
# --------------------------------------------------------------------------
echo -e "${YELLOW}[1/5] Deploying monitoring brain: ${BRAIN_STACK}...${NC}"
aws cloudformation deploy \
  --template-file "${BRAIN_TEMPLATE}" \
  --stack-name "${BRAIN_STACK}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Project=deception-monitoring ManagedBy=cloudformation \
  --no-fail-on-empty-changeset
echo -e "${GREEN}  ✓ Monitoring brain deployed${NC}"
echo ""

# --------------------------------------------------------------------------
# STEP 2: Get outputs
# --------------------------------------------------------------------------
echo -e "${YELLOW}[2/5] Retrieving stack outputs...${NC}"
LAMBDA_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${BRAIN_STACK}" \
  --region "${REGION}" \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionArn`].OutputValue' \
  --output text)

INVOKE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${BRAIN_STACK}" \
  --region "${REGION}" \
  --query 'Stacks[0].Outputs[?OutputKey==`InvokeLambdaRoleArn`].OutputValue' \
  --output text)

SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${BRAIN_STACK}" \
  --region "${REGION}" \
  --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
  --output text)

echo -e "${GREEN}  ✓ Lambda:      ${LAMBDA_ARN}${NC}"
echo -e "${GREEN}  ✓ Invoke Role: ${INVOKE_ROLE_ARN}${NC}"
echo -e "${GREEN}  ✓ SNS Topic:   ${SNS_TOPIC_ARN}${NC}"
echo ""

# --------------------------------------------------------------------------
# STEP 3: Deploy Detection Rules
# --------------------------------------------------------------------------
echo -e "${YELLOW}[3/5] Deploying detection rules: ${RULES_STACK}...${NC}"
aws cloudformation deploy \
  --template-file "${RULES_TEMPLATE}" \
  --stack-name "${RULES_STACK}" \
  --region "${REGION}" \
  --parameter-overrides \
    LambdaArn="${LAMBDA_ARN}" \
    InvokeLambdaRoleArn="${INVOKE_ROLE_ARN}" \
  --tags Project=deception-monitoring ManagedBy=cloudformation \
  --no-fail-on-empty-changeset
echo -e "${GREEN}  ✓ Detection rules deployed (19 scenario rules)${NC}"
echo ""

# --------------------------------------------------------------------------
# STEP 4: Subscribe emails
# --------------------------------------------------------------------------
echo -e "${YELLOW}[4/5] Configuring email subscriptions...${NC}"

ALL_EMAILS=("${DEFAULT_EMAILS[@]}")

echo -e "  Default subscribers:"
for email in "${DEFAULT_EMAILS[@]}"; do
  echo -e "    • ${email}"
done
echo ""

read -rp "  Add additional email subscribers? (y/N): " ADD_MORE
if [[ "${ADD_MORE}" =~ ^[Yy]$ ]]; then
  echo "  Enter emails one per line (empty line to finish):"
  while true; do
    read -rp "    email: " NEW_EMAIL
    [[ -z "${NEW_EMAIL}" ]] && break
    ALL_EMAILS+=("${NEW_EMAIL}")
  done
fi

echo ""
for email in "${ALL_EMAILS[@]}"; do
  EXISTING=$(aws sns list-subscriptions-by-topic \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --region "${REGION}" \
    --query "Subscriptions[?Endpoint=='${email}'].Endpoint" \
    --output text 2>/dev/null || echo "")
  if [[ -n "${EXISTING}" ]]; then
    echo -e "  ${GREEN}✓${NC} ${email} (already subscribed)"
  else
    aws sns subscribe \
      --topic-arn "${SNS_TOPIC_ARN}" \
      --protocol email \
      --notification-endpoint "${email}" \
      --region "${REGION}" > /dev/null
    echo -e "  ${GREEN}✓${NC} ${email} (pending confirmation)"
  fi
done
echo ""

# --------------------------------------------------------------------------
# STEP 5: Add EventBus permissions for dev accounts
# --------------------------------------------------------------------------
echo -e "${YELLOW}[5/5] Configuring EventBus permissions...${NC}"
echo ""
echo "  Enter dev account IDs to allow forwarding (one per line, empty to finish):"

while true; do
  read -rp "    account ID: " DEV_ACCOUNT_ID
  [[ -z "${DEV_ACCOUNT_ID}" ]] && break
  aws events put-permission \
    --event-bus-name deception-global-event-bus \
    --action events:PutEvents \
    --principal "${DEV_ACCOUNT_ID}" \
    --statement-id "AllowAccount-${DEV_ACCOUNT_ID}" \
    --region "${REGION}" 2>/dev/null || echo "    (permission may already exist)"
  echo -e "  ${GREEN}✓${NC} Account ${DEV_ACCOUNT_ID} authorized"
done

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  CSC Prod Deployment Complete              ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e "  Stacks:"
echo -e "    • ${BRAIN_STACK} — SNS, Lambda, EventBus, IAM roles"
echo -e "    • ${RULES_STACK} — 19 detection rules on global bus"
echo ""
echo -e "  ${YELLOW}Next: Deploy forwarding rules in each dev account${NC}"
echo -e "  cd ../dev-account-forwarding && bash deploy.sh"
echo ""
