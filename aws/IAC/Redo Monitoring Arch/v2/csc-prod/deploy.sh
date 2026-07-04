#!/bin/bash
# ==============================================================================
# deploy.sh — CSC Prod v2: Monitoring Brain + Detection Rules
# Uses deception-v2-* naming. Does NOT touch v1 resources.
# Run with CSC Prod credentials (913511275171)
# ==============================================================================

set -euo pipefail

REGION="us-west-2"
BRAIN_STACK="deception-v2-monitoring-brain"
RULES_STACK="deception-v2-detection-rules"
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
echo -e "${CYAN}  CSC Prod v2 — Brain + Detection Rules     ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "  Account: ${ACCOUNT_ID}"
echo -e "  Region:  ${REGION}"
echo -e "  Version: v2 (separate from v1)"
echo ""

if [[ "${ACCOUNT_ID}" != "913511275171" ]]; then
  echo -e "${RED}  ERROR: Must run with CSC Prod credentials (913511275171)${NC}"
  exit 1
fi

# --------------------------------------------------------------------------
# STEP 1: Deploy Brain
# --------------------------------------------------------------------------
echo -e "${YELLOW}[1/5] Deploying v2 brain: ${BRAIN_STACK}...${NC}"
aws cloudformation deploy \
  --template-file "${BRAIN_TEMPLATE}" \
  --stack-name "${BRAIN_STACK}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Project=deception-monitoring ManagedBy=cloudformation Version=v2 \
  --no-fail-on-empty-changeset
echo -e "${GREEN}  ✓ Brain deployed${NC}"
echo ""

# --------------------------------------------------------------------------
# STEP 2: Get outputs
# --------------------------------------------------------------------------
echo -e "${YELLOW}[2/5] Retrieving outputs...${NC}"
LAMBDA_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${BRAIN_STACK}" --region "${REGION}" \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionArn`].OutputValue' --output text)

INVOKE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${BRAIN_STACK}" --region "${REGION}" \
  --query 'Stacks[0].Outputs[?OutputKey==`InvokeLambdaRoleArn`].OutputValue' --output text)

SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${BRAIN_STACK}" --region "${REGION}" \
  --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' --output text)

echo -e "${GREEN}  ✓ Lambda:      ${LAMBDA_ARN}${NC}"
echo -e "${GREEN}  ✓ Invoke Role: ${INVOKE_ROLE_ARN}${NC}"
echo -e "${GREEN}  ✓ SNS Topic:   ${SNS_TOPIC_ARN}${NC}"
echo ""

# --------------------------------------------------------------------------
# STEP 3: Deploy Detection Rules
# --------------------------------------------------------------------------
echo -e "${YELLOW}[3/5] Deploying v2 detection rules: ${RULES_STACK}...${NC}"
aws cloudformation deploy \
  --template-file "${RULES_TEMPLATE}" \
  --stack-name "${RULES_STACK}" \
  --region "${REGION}" \
  --parameter-overrides \
    LambdaArn="${LAMBDA_ARN}" \
    InvokeLambdaRoleArn="${INVOKE_ROLE_ARN}" \
  --tags Project=deception-monitoring ManagedBy=cloudformation Version=v2 \
  --no-fail-on-empty-changeset
echo -e "${GREEN}  ✓ 19 detection rules deployed${NC}"
echo ""

# --------------------------------------------------------------------------
# STEP 4: Subscribe emails
# --------------------------------------------------------------------------
echo -e "${YELLOW}[4/5] Email subscriptions...${NC}"
ALL_EMAILS=("${DEFAULT_EMAILS[@]}")
echo "  Default: ${DEFAULT_EMAILS[*]}"
read -rp "  Add more? (y/N): " ADD_MORE
if [[ "${ADD_MORE}" =~ ^[Yy]$ ]]; then
  while true; do
    read -rp "    email: " NEW_EMAIL
    [[ -z "${NEW_EMAIL}" ]] && break
    ALL_EMAILS+=("${NEW_EMAIL}")
  done
fi
for email in "${ALL_EMAILS[@]}"; do
  EXISTING=$(aws sns list-subscriptions-by-topic --topic-arn "${SNS_TOPIC_ARN}" --region "${REGION}" \
    --query "Subscriptions[?Endpoint=='${email}'].Endpoint" --output text 2>/dev/null || echo "")
  if [[ -n "${EXISTING}" ]]; then
    echo -e "  ${GREEN}✓${NC} ${email} (subscribed)"
  else
    aws sns subscribe --topic-arn "${SNS_TOPIC_ARN}" --protocol email \
      --notification-endpoint "${email}" --region "${REGION}" > /dev/null
    echo -e "  ${GREEN}✓${NC} ${email} (pending)"
  fi
done
echo ""

# --------------------------------------------------------------------------
# STEP 5: EventBus permissions
# --------------------------------------------------------------------------
echo -e "${YELLOW}[5/5] EventBus permissions...${NC}"
echo "  Enter dev account IDs (empty to finish):"
while true; do
  read -rp "    account: " DEV_ID
  [[ -z "${DEV_ID}" ]] && break
  aws events put-permission \
    --event-bus-name deception-v2-global-bus \
    --action events:PutEvents \
    --principal "${DEV_ID}" \
    --statement-id "AllowAccount-${DEV_ID}" \
    --region "${REGION}" 2>/dev/null || echo "    (may already exist)"
  echo -e "  ${GREEN}✓${NC} ${DEV_ID} authorized"
done

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  v2 CSC Prod Complete                      ${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "  Stacks: ${BRAIN_STACK}, ${RULES_STACK}"
echo -e "  Next: cd ../dev-account && bash deploy.sh"
echo ""
