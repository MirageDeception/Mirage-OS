#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 14 (SNS Critical Alerts Topic)
#
# This script:
#   1. Deploys the CloudFormation stack (SNS topic + subscriptions + IAM role)
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and SNS topics
#
set -euo pipefail

# ---------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-14"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID automatically
# ---------------------------------------------------------------
info "Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ok "Account ID: ${ACCOUNT_ID}"

# ---------------------------------------------------------------
# Deploy the CloudFormation stack
# ---------------------------------------------------------------
info "Deploying CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides AccountId="${ACCOUNT_ID}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

ok "Stack deployed successfully."

# ---------------------------------------------------------------
# Wait for stack to stabilize
# ---------------------------------------------------------------
info "Waiting for stack to stabilize..."
aws cloudformation wait stack-create-complete \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" 2>/dev/null || true

# ---------------------------------------------------------------
# Verify subscriptions are PendingConfirmation
# ---------------------------------------------------------------
info "Verifying SNS subscriptions..."
TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='TopicArn'].OutputValue" \
  --output text)

SUBS=$(aws sns list-subscriptions-by-topic \
  --topic-arn "${TOPIC_ARN}" \
  --region "${REGION}" \
  --query "Subscriptions[].{Protocol: Protocol, Endpoint: Endpoint, SubscriptionArn: SubscriptionArn}" \
  --output table 2>/dev/null || true)

if [ -n "${SUBS}" ]; then
  ok "Subscriptions created (PendingConfirmation — no real delivery):"
  echo "${SUBS}"
else
  warn "Subscriptions may still be propagating."
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 14 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Topic    : prod-alerts-critical"
echo "  Role     : alerts-readonly-role (discovery)"
echo "  Subs     :"
echo "    - HTTPS: hooks.prod.internal.corp/alerts/critical"
echo "    - Email: oncall-sre@acme-corp.com"
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. All resources are live."
