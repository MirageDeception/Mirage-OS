#!/bin/bash
# ==============================================================================
# cleanup-v2.sh — Remove ALL v2 resources from both accounts
# Run this to completely revert to v1-only state.
#
# USAGE:
#   1. Run with dev account credentials first
#   2. Then run with CSC Prod credentials
#   The script detects which account you're in and cleans accordingly.
# ==============================================================================

set -euo pipefail

REGION="us-west-2"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${RED}============================================${NC}"
echo -e "${RED}  CLEANUP v2 — Delete all v2 resources      ${NC}"
echo -e "${RED}============================================${NC}"
echo ""
echo -e "  Account: ${ACCOUNT_ID}"
echo -e "  Region:  ${REGION}"
echo ""

read -rp "  Are you sure you want to delete all v2 resources? (type 'yes'): " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "  Aborted."
  exit 0
fi
echo ""

# --------------------------------------------------------------------------
# DEV ACCOUNT cleanup
# --------------------------------------------------------------------------
if [[ "${ACCOUNT_ID}" != "913511275171" ]]; then
  echo -e "${YELLOW}  Cleaning dev account v2 resources...${NC}"

  # Delete forwarding stack
  echo -e "  Deleting stack: deception-v2-forwarding..."
  aws cloudformation delete-stack \
    --stack-name deception-v2-forwarding \
    --region "${REGION}" 2>/dev/null || true
  aws cloudformation wait stack-delete-complete \
    --stack-name deception-v2-forwarding \
    --region "${REGION}" 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} deception-v2-forwarding deleted"

  echo ""
  echo -e "${GREEN}  Dev account v2 cleanup complete.${NC}"
  echo -e "  Now run this script again with CSC Prod credentials."

# --------------------------------------------------------------------------
# CSC PROD cleanup
# --------------------------------------------------------------------------
elif [[ "${ACCOUNT_ID}" == "913511275171" ]]; then
  echo -e "${YELLOW}  Cleaning CSC Prod v2 resources...${NC}"

  # Delete detection rules stack first (depends on brain)
  echo -e "  Deleting stack: deception-v2-detection-rules..."
  aws cloudformation delete-stack \
    --stack-name deception-v2-detection-rules \
    --region "${REGION}" 2>/dev/null || true
  aws cloudformation wait stack-delete-complete \
    --stack-name deception-v2-detection-rules \
    --region "${REGION}" 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} deception-v2-detection-rules deleted"

  # Delete brain stack
  echo -e "  Deleting stack: deception-v2-monitoring-brain..."
  aws cloudformation delete-stack \
    --stack-name deception-v2-monitoring-brain \
    --region "${REGION}" 2>/dev/null || true
  aws cloudformation wait stack-delete-complete \
    --stack-name deception-v2-monitoring-brain \
    --region "${REGION}" 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} deception-v2-monitoring-brain deleted"

  # Remove bus permission for dev account
  echo -e "  Removing bus permissions..."
  aws events remove-permission \
    --event-bus-name deception-v2-global-bus \
    --statement-id "AllowAccount-046574264211" \
    --region "${REGION}" 2>/dev/null || true

  echo ""
  echo -e "${GREEN}  CSC Prod v2 cleanup complete.${NC}"
fi

echo ""
echo -e "${CYAN}  All v2 resources removed. v1 is untouched.${NC}"
echo ""
