#!/bin/bash
# ==============================================================================
# remove-hub.sh — Remove ALL v2 resources from the HUB account
# ==============================================================================

set -euo pipefail

# Inputs
REGION=$1
WHITELISTED_ARNS=$2 # Not strictly needed for teardown, but kept for signature consistency if needed

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "============================================"
echo -e "  CLEANUP v2 — Delete Hub Resources         "
echo -e "============================================"
echo -e "  Hub Account: ${ACCOUNT_ID}"
echo -e "  Region:      ${REGION}"
echo ""

echo -e "  Deleting stack: deception-v2-service-rules..."
aws cloudformation delete-stack \
  --stack-name deception-v2-service-rules \
  --region "${REGION}" 2>/dev/null || true
aws cloudformation wait stack-delete-complete \
  --stack-name deception-v2-service-rules \
  --region "${REGION}" 2>/dev/null || true
echo -e "  ✓ deception-v2-service-rules deleted"

echo -e "  Deleting stack: deception-v2-monitoring-brain..."
aws cloudformation delete-stack \
  --stack-name deception-v2-monitoring-brain \
  --region "${REGION}" 2>/dev/null || true
aws cloudformation wait stack-delete-complete \
  --stack-name deception-v2-monitoring-brain \
  --region "${REGION}" 2>/dev/null || true
echo -e "  ✓ deception-v2-monitoring-brain deleted"

echo ""
echo -e "  Hub account v2 cleanup complete."
