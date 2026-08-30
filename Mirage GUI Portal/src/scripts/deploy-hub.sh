#!/bin/bash
# MIRAGE Hub Deployment Script
# This script is automatically executed by the Next.js API Route (/api/deploy-brain).
# It inherits AWS credentials (STS AssumeRole) via environment variables.

set -e # Exit immediately if any command fails

REGION=${1:-"us-west-2"}
WHITELISTED_ARNS=${2:-""}

echo "==========================================="
echo "🚀 Starting MIRAGE Hub Deployment"
echo "Region: $REGION"
echo "==========================================="

# Resolve absolute paths assuming the script is run from the project root
BRAIN_TEMPLATE="src/templates/hub/monitoring-brain.yaml"
RULES_TEMPLATE="src/templates/hub/service-rules.yaml"

# 1. Deploy the Monitoring Brain (Base Infrastructure)
echo ""
echo "📦 Deploying Base Infrastructure (Lambda, SNS, EventBus)..."
if [ -n "$WHITELISTED_ARNS" ]; then
    echo "Applying Custom Whitelist: $WHITELISTED_ARNS"
    aws cloudformation deploy \
        --template-file "$BRAIN_TEMPLATE" \
        --stack-name deception-v2-monitoring-brain \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" \
        --parameter-overrides WhitelistedARNs="$WHITELISTED_ARNS"
else
    aws cloudformation deploy \
        --template-file "$BRAIN_TEMPLATE" \
        --stack-name deception-v2-monitoring-brain \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"
fi

# 2. Deploy the Service Rules (depends on the base infrastructure being complete)
echo ""
echo "🛡️ Deploying Service-Specific EventBridge Rules..."
aws cloudformation deploy \
    --template-file "$RULES_TEMPLATE" \
    --stack-name deception-v2-service-rules \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"

echo ""
echo "✅ Hub Deployment Completed Successfully!"
echo "==========================================="
