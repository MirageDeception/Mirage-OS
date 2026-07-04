#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 16 (KMS Key Lure)
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
NC='\033[0m' # No Color

step() { echo -e "\n${CYAN}[STEP $1]${NC} $2"; }
info() { echo -e "  ${GREEN}[+]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
attack() { echo -e "  ${RED}[ATTACK]${NC} $1"; }

echo -e "${RED}"
echo "============================================="
echo "  SCENARIO 16 — ABUSE CHAIN"
echo "  KMS Customer Data Encryption Key Lure"
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
step "2" "Assuming lure role: kms-audit-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/kms-audit-readonly-role"
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
step "3" "Listing KMS aliases (kms:ListAliases)"
# ---------------------------------------------------------------
attack "kms:ListAliases"
aws kms list-aliases \
  --query "Aliases[?starts_with(AliasName, 'alias/prod-')].{Alias: AliasName, KeyId: TargetKeyId}" \
  --output table

KEY_ID=$(aws kms list-aliases \
  --query "Aliases[?AliasName=='alias/prod-customer-data-encryption'].TargetKeyId" \
  --output text)
info "Target key identified: ${KEY_ID}"

# ---------------------------------------------------------------
step "4" "Describing key metadata (kms:DescribeKey)"
# ---------------------------------------------------------------
attack "kms:DescribeKey → ${KEY_ID}"
aws kms describe-key \
  --key-id "${KEY_ID}" \
  --output json

# ---------------------------------------------------------------
step "5" "Listing key grants (kms:ListGrants)"
# ---------------------------------------------------------------
attack "kms:ListGrants → ${KEY_ID}"
GRANTS=$(aws kms list-grants \
  --key-id "${KEY_ID}" \
  --output json 2>/dev/null || echo '{"Grants": []}')
echo "${GRANTS}" | jq '.'

GRANT_COUNT=$(echo "${GRANTS}" | jq '.Grants | length')
info "Found ${GRANT_COUNT} grant(s)"

# ---------------------------------------------------------------
step "6" "Reading key policy (kms:GetKeyPolicy)"
# ---------------------------------------------------------------
attack "kms:GetKeyPolicy → ${KEY_ID}"
aws kms get-key-policy \
  --key-id "${KEY_ID}" \
  --policy-name default \
  --output text | jq '.'

# ---------------------------------------------------------------
step "7" "Attempting decrypt (kms:Decrypt — expect DENIED)"
# ---------------------------------------------------------------
warn "Attempting decrypt operation — this should be denied..."
attack "kms:Decrypt → ${KEY_ID}"

# Generate a dummy ciphertext blob to attempt decryption
DUMMY_BLOB=$(echo "test-plaintext" | base64)

if aws kms decrypt \
  --key-id "${KEY_ID}" \
  --ciphertext-blob fileb://<(echo "test" | base64 -d) \
  --output json 2>/tmp/scenario16-decrypt-error; then
  warn "Decrypt succeeded unexpectedly!"
else
  info "Decrypt DENIED as expected"
  echo ""
  echo -e "  ${YELLOW}Error:${NC}"
  cat /tmp/scenario16-decrypt-error | head -5
  rm -f /tmp/scenario16-decrypt-error
fi

# ---------------------------------------------------------------
step "8" "Summary of extracted intelligence"
# ---------------------------------------------------------------
echo ""
warn "The following information was extracted from the KMS key:"
echo ""
echo "  • Key alias: alias/prod-customer-data-encryption"
echo "  • Key purpose: Customer PII encryption (payment and user data)"
echo "  • Key policy reveals service principals: Lambda, RDS, S3"
echo "  • Key rotation: enabled"
echo "  • Data classification: PII"
echo ""
warn "Decrypt/Encrypt operations are explicitly denied for this role."

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
echo "  • CloudTrail: AssumeRole on kms-audit-readonly-role"
echo "  • CloudTrail: ListAliases"
echo "  • CloudTrail: DescribeKey on prod-customer-data-encryption"
echo "  • CloudTrail: ListGrants on prod-customer-data-encryption"
echo "  • CloudTrail: GetKeyPolicy on prod-customer-data-encryption"
echo "  • CloudTrail: Decrypt DENIED on prod-customer-data-encryption"
echo ""
