#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 9 and seed all SSM parameters
#
# This script:
#   1. Deploys the CloudFormation stack (3 IAM roles + 3 SSM parameters)
#   2. Seeds SSM parameter /prod/auth/oidc-config with fake OIDC provider config
#   3. Seeds SSM parameter /prod/data/lake-credentials with fake data lake credentials
#   4. Seeds SSM parameter /prod/admin/console-credentials with fake admin console credentials
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Sufficient IAM permissions to create CloudFormation stacks,
#     IAM roles, and SSM parameters
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
STACK_NAME="deception-scenario-9"
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
# Seed SSM Parameter: OIDC config
# ---------------------------------------------------------------
info "Updating SSM parameter: /prod/auth/oidc-config ..."
aws ssm put-parameter \
  --name "/prod/auth/oidc-config" \
  --value file://fake-data/oidc-config.json \
  --type String \
  --overwrite \
  --region "${REGION}"
ok "OIDC config parameter seeded."

# ---------------------------------------------------------------
# Seed SSM Parameter: data lake credentials
# ---------------------------------------------------------------
info "Updating SSM parameter: /prod/data/lake-credentials ..."
aws ssm put-parameter \
  --name "/prod/data/lake-credentials" \
  --value file://fake-data/lake-credentials.json \
  --type String \
  --overwrite \
  --region "${REGION}"
ok "Data lake credentials parameter seeded."

# ---------------------------------------------------------------
# Seed SSM Parameter: admin console credentials
# ---------------------------------------------------------------
info "Updating SSM parameter: /prod/admin/console-credentials ..."
aws ssm put-parameter \
  --name "/prod/admin/console-credentials" \
  --value file://fake-data/console-credentials.json \
  --type String \
  --overwrite \
  --region "${REGION}"
ok "Admin console credentials parameter seeded."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 9 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Roles    :"
echo "    - prod-microservice-auth-role  (A → assumes B)"
echo "    - prod-microservice-data-role  (B → assumes C)"
echo "    - prod-microservice-admin-role (C → assumes A)"
echo "  SSM      :"
echo "    - /prod/auth/oidc-config"
echo "    - /prod/data/lake-credentials"
echo "    - /prod/admin/console-credentials"
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. All resources are live."
