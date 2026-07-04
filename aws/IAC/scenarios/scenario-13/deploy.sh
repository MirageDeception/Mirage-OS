#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 15 and seed CloudWatch log entries
#
# This script:
#   1. Deploys the CloudFormation stack (CloudWatch Log Group + IAM role)
#   2. Creates log streams for each simulated service instance
#   3. Seeds 14 log entries across 3 streams with realistic application logs
#      including accidentally leaked credentials
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - jq installed
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and CloudWatch Logs resources
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
STACK_NAME="deception-scenario-15"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
LOG_GROUP="/prod/payment-service/application"
LOG_ENTRIES_FILE="fake-data/log-entries.json"

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
# Seed log streams and entries from log-entries.json
# ---------------------------------------------------------------
info "Seeding CloudWatch log entries from ${LOG_ENTRIES_FILE} ..."

# Base timestamp: 2024-11-15T02:14:00Z in milliseconds
BASE_TIMESTAMP=1731636840000

# Iterate over each stream defined in the JSON
for STREAM_NAME in $(jq -r '.streams | keys[]' "${LOG_ENTRIES_FILE}"); do
  info "Creating log stream: ${STREAM_NAME}"
  aws logs create-log-stream \
    --log-group-name "${LOG_GROUP}" \
    --log-stream-name "${STREAM_NAME}" \
    --region "${REGION}" 2>/dev/null || true

  # Build the log events array for this stream
  EVENTS="["
  FIRST=true
  for ROW in $(jq -c ".streams[\"${STREAM_NAME}\"][]" "${LOG_ENTRIES_FILE}"); do
    OFFSET=$(echo "${ROW}" | jq -r '.timestamp_offset')
    MESSAGE=$(echo "${ROW}" | jq -r '.message')
    TS=$((BASE_TIMESTAMP + OFFSET))

    if [ "${FIRST}" = true ]; then
      FIRST=false
    else
      EVENTS="${EVENTS},"
    fi
    # Escape the message for JSON embedding
    ESCAPED_MSG=$(echo "${MESSAGE}" | jq -Rs '.')
    EVENTS="${EVENTS}{\"timestamp\":${TS},\"message\":${ESCAPED_MSG}}"
  done
  EVENTS="${EVENTS}]"

  # Put log events for this stream
  echo "${EVENTS}" | jq '.' > /tmp/scenario15-events.json
  aws logs put-log-events \
    --log-group-name "${LOG_GROUP}" \
    --log-stream-name "${STREAM_NAME}" \
    --log-events "file:///tmp/scenario15-events.json" \
    --region "${REGION}" > /dev/null

  EVENT_COUNT=$(echo "${EVENTS}" | jq 'length')
  ok "Seeded ${EVENT_COUNT} events into stream: ${STREAM_NAME}"
done

# Clean up temp file
rm -f /tmp/scenario15-events.json

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 15 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack     : ${STACK_NAME}"
echo "  Region    : ${REGION}"
echo "  Log Group : ${LOG_GROUP}"
echo "  Role      : log-analysis-readonly-role (discovery)"
echo "  Streams   :"
echo "    - payment-processor/i-0a3b7c9d1e5f2a4b6"
echo "    - auth-service/i-0b4c8d2e6f3a5b7c9"
echo "    - bootstrap/i-0c5d9e3f7a4b6c8d0"
echo "  Entries   : 14 log events seeded"
echo -e "${GREEN}=============================================${NC}"
echo ""
warn "Credential-leaking entries include:"
echo "  • DB connection string in stack trace"
echo "  • Stripe API key in debug HTTP headers"
echo "  • Plaintext password in auth failure log"
echo "  • Full environment variable dump with secrets"
echo ""
ok "Done. All resources are live."
