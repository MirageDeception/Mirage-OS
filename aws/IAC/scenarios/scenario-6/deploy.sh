#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 6 (Lambda Blueprint)
#
# This is the base Lambda lure scenario. It deploys a Lambda function with
# hardcoded secrets in environment variables and a read-only discovery role.
# Optionally includes S3, Secrets Manager, and SSM as downstream targets.
#
# Scenarios 7 and 8 can link to this as a base, or deploy standalone.
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
set -euo pipefail

# ---------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-6"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID
# ---------------------------------------------------------------
info "Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ok "Account ID: ${ACCOUNT_ID}"

# ---------------------------------------------------------------
# Ask which services to include
# ---------------------------------------------------------------
echo ""
echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}  Scenario 6 — Lambda Blueprint${NC}"
echo -e "${CYAN}  Select downstream pivot targets:${NC}"
echo -e "${CYAN}=============================================${NC}"
echo ""

read -rp "  Include S3 bucket (pipeline artifacts)? [Y/n]: " INCLUDE_S3
INCLUDE_S3=${INCLUDE_S3:-Y}
if [ "${INCLUDE_S3}" = "Y" ] || [ "${INCLUDE_S3}" = "y" ]; then
  INCLUDE_S3="true"
else
  INCLUDE_S3="false"
fi

read -rp "  Include SSM parameter (pipeline config)? [Y/n]: " INCLUDE_SSM
INCLUDE_SSM=${INCLUDE_SSM:-Y}
if [ "${INCLUDE_SSM}" = "Y" ] || [ "${INCLUDE_SSM}" = "y" ]; then
  INCLUDE_SSM="true"
else
  INCLUDE_SSM="false"
fi

read -rp "  Include Secrets Manager (\$0.40/mo)? [y/N]: " INCLUDE_SM
INCLUDE_SM=${INCLUDE_SM:-N}
if [ "${INCLUDE_SM}" = "Y" ] || [ "${INCLUDE_SM}" = "y" ]; then
  INCLUDE_SM="true"
else
  INCLUDE_SM="false"
fi

# ---------------------------------------------------------------
# Show cost estimate
# ---------------------------------------------------------------
echo ""
echo -e "${YELLOW}--- Cost Estimate ---${NC}"
COST="0.00"
echo "  Lambda (never invoked):       \$0.00"
if [ "${INCLUDE_S3}" = "true" ]; then
  echo "  S3 (small JSON files):        \$0.00"
fi
if [ "${INCLUDE_SSM}" = "true" ]; then
  echo "  SSM Standard (1 param):       \$0.00"
fi
if [ "${INCLUDE_SM}" = "true" ]; then
  echo "  Secrets Manager (1 secret):   \$0.40"
  COST="0.40"
fi
echo "  IAM resources:                \$0.00"
echo -e "  ${GREEN}Total: \$${COST}/mo${NC}"
echo ""

read -rp "  Deploy? [Y/n]: " DEPLOY_CONFIRM
DEPLOY_CONFIRM=${DEPLOY_CONFIRM:-Y}
if [ "${DEPLOY_CONFIRM}" != "Y" ] && [ "${DEPLOY_CONFIRM}" != "y" ]; then
  echo "Aborted."
  exit 0
fi

# ---------------------------------------------------------------
# Deploy the CloudFormation stack
# ---------------------------------------------------------------
info "Deploying CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides \
      AccountId="${ACCOUNT_ID}" \
      IncludeS3="${INCLUDE_S3}" \
      IncludeSecretsManager="${INCLUDE_SM}" \
      IncludeSSM="${INCLUDE_SSM}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

ok "Stack deployed successfully."

# ---------------------------------------------------------------
# Seed data stores (conditional)
# ---------------------------------------------------------------
BUCKET_NAME="prod-data-sync-artifacts-${ACCOUNT_ID}"

if [ "${INCLUDE_S3}" = "true" ]; then
  info "Seeding S3 bucket: ${BUCKET_NAME} ..."
  aws s3 cp fake-data/pipeline-config.json \
    "s3://${BUCKET_NAME}/config/pipeline-config.json" \
    --region "${REGION}"
  aws s3 cp fake-data/partner-api-keys.json \
    "s3://${BUCKET_NAME}/credentials/partner-api-keys.json" \
    --region "${REGION}"
  ok "S3 seeded."
fi

if [ "${INCLUDE_SM}" = "true" ]; then
  info "Seeding Secrets Manager: prod/data-sync/api-credentials ..."
  aws secretsmanager put-secret-value \
    --secret-id "prod/data-sync/api-credentials" \
    --secret-string file://fake-data/api-credentials.json \
    --region "${REGION}"
  ok "Secret seeded."
fi

if [ "${INCLUDE_SSM}" = "true" ]; then
  info "Seeding SSM parameter: /prod/data-sync/config ..."
  aws ssm put-parameter \
    --name "/prod/data-sync/config" \
    --value file://fake-data/data-sync-config.json \
    --type String \
    --overwrite \
    --region "${REGION}"
  ok "SSM parameter seeded."
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 6 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Lambda   : prod-data-sync-processor"
echo "  Role     : lambda-ops-readonly-role (discovery, read-only)"
echo "  Exec Role: prod-data-sync-exec-role"
echo "  S3       : $([ "${INCLUDE_S3}" = "true" ] && echo "${BUCKET_NAME}" || echo "not included")"
echo "  Secret   : $([ "${INCLUDE_SM}" = "true" ] && echo "prod/data-sync/api-credentials" || echo "not included")"
echo "  SSM      : $([ "${INCLUDE_SSM}" = "true" ] && echo "/prod/data-sync/config" || echo "not included")"
echo "  Cost     : \$${COST}/mo"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${CYAN}[*] This is the Lambda blueprint. Scenarios 7 and 8 can link to it.${NC}"
ok "Done."
