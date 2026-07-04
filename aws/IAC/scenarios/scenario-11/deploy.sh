#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 13 and seed DLQ with fake payment events
#
# This script:
#   1. Deploys the CloudFormation stack (IAM role + SQS FIFO queue + DLQ)
#   2. Sends fake failed payment event messages to the DLQ
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and SQS queues
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
STACK_NAME="deception-scenario-13"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
EVENTS_FILE="fake-data/payment-events.json"
MESSAGE_GROUP_ID="payment-processing"

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
# Get the DLQ URL from stack outputs
# ---------------------------------------------------------------
info "Retrieving DLQ URL from stack outputs..."
DLQ_URL=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='DLQUrl'].OutputValue" \
  --output text)
ok "DLQ URL: ${DLQ_URL}"

# ---------------------------------------------------------------
# Seed SQS DLQ: fake failed payment event messages
# ---------------------------------------------------------------
info "Sending fake payment events to DLQ ..."

EVENT_COUNT=$(jq length "${EVENTS_FILE}")
CURRENT=0

for row in $(jq -c '.[]' "${EVENTS_FILE}"); do
  CURRENT=$((CURRENT + 1))
  TXN_ID=$(echo "$row" | jq -r '.transaction_id')
  info "  Sending event ${CURRENT}/${EVENT_COUNT}: ${TXN_ID}"

  aws sqs send-message \
    --queue-url "${DLQ_URL}" \
    --message-body "$row" \
    --message-group-id "${MESSAGE_GROUP_ID}" \
    --region "${REGION}" \
    --output text > /dev/null
done

ok "Sent ${EVENT_COUNT} payment events to DLQ."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 13 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Role     : payment-queue-readonly-role"
echo "  Queue    : prod-payment-events.fifo"
echo "  DLQ      : prod-payment-events-dlq.fifo"
echo "  Messages : ${EVENT_COUNT} payment events in DLQ"
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. All resources are live."
