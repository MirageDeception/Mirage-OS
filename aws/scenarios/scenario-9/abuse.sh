#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 11 (DynamoDB Customer Profiles Lure)
#
# This script walks through the attack chain step by step:
#   Assume role → list tables → describe table → scan records → extract PII
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
echo "  SCENARIO 11 — ABUSE CHAIN"
echo "  DynamoDB Fake Customer Profiles"
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
step "2" "Assuming lure role: customer-data-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/customer-data-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-customer-data" \
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
info "Target table identified: prod-customer-profiles"

# ---------------------------------------------------------------
step "4" "Describing table schema (dynamodb:DescribeTable)"
# ---------------------------------------------------------------
attack "dynamodb:DescribeTable → prod-customer-profiles"
aws dynamodb describe-table \
  --table-name "prod-customer-profiles" \
  --region us-west-2 \
  --query "Table.{TableName:TableName,KeySchema:KeySchema,ItemCount:ItemCount,TableStatus:TableStatus,PointInTimeRecovery:PointInTimeRecoveryDescription}" \
  --output table

# ---------------------------------------------------------------
step "5" "Scanning all customer records (dynamodb:Scan)"
# ---------------------------------------------------------------
attack "dynamodb:Scan → prod-customer-profiles"
SCAN_RESULT=$(aws dynamodb scan \
  --table-name "prod-customer-profiles" \
  --region us-west-2 \
  --output json)

ITEM_COUNT=$(echo "$SCAN_RESULT" | jq '.Count')
info "Retrieved ${ITEM_COUNT} customer records"

# ---------------------------------------------------------------
step "6" "Extracting customer PII"
# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}--- Extracted Customer Data ---${NC}"
echo "$SCAN_RESULT" | jq -r '.Items[] | "  [\(.customer_id.S)] \(.full_name.S) | \(.email.S) | \(.phone.S) | card: \(.card_token.S) | status: \(.account_status.S) | LTV: $\(.lifetime_value.N)"'

echo ""
warn "Extracted fields: customer_id, full_name, email, phone, card_token, account_status, lifetime_value"

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
echo "  • CloudTrail: AssumeRole on customer-data-readonly-role"
echo "  • CloudTrail: ListTables"
echo "  • CloudTrail: DescribeTable on prod-customer-profiles"
echo "  • CloudTrail: Scan on prod-customer-profiles"
echo ""
