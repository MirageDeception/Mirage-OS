#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 20 and seed SSM parameter chain
#
# This script:
#   1. Deploys the CloudFormation stack (IAM role + 5 SSM parameters)
#   2. Seeds each SSM parameter with JSON containing credentials and
#      a see_also field pointing to the next parameter in the chain
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
STACK_NAME="deception-scenario-20"
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
# Seed SSM Parameter: /prod/db/primary
# ---------------------------------------------------------------
info "Seeding SSM parameter: /prod/db/primary ..."
aws ssm put-parameter \
  --name "/prod/db/primary" \
  --value file://fake-data/db-primary.json \
  --type String \
  --overwrite \
  --region "${REGION}"
ok "Primary DB config seeded (see_also → /prod/db/replica)"

# ---------------------------------------------------------------
# Seed SSM Parameter: /prod/db/replica
# ---------------------------------------------------------------
info "Seeding SSM parameter: /prod/db/replica ..."
aws ssm put-parameter \
  --name "/prod/db/replica" \
  --value file://fake-data/db-replica.json \
  --type String \
  --overwrite \
  --region "${REGION}"
ok "Replica DB config seeded (see_also → /prod/db/backup-config)"

# ---------------------------------------------------------------
# Seed SSM Parameter: /prod/db/backup-config
# ---------------------------------------------------------------
info "Seeding SSM parameter: /prod/db/backup-config ..."
aws ssm put-parameter \
  --name "/prod/db/backup-config" \
  --value file://fake-data/db-backup-config.json \
  --type String \
  --overwrite \
  --region "${REGION}"
ok "Backup config seeded (see_also → /prod/db/encryption-config)"

# ---------------------------------------------------------------
# Seed SSM Parameter: /prod/db/encryption-config
# ---------------------------------------------------------------
info "Seeding SSM parameter: /prod/db/encryption-config ..."
aws ssm put-parameter \
  --name "/prod/db/encryption-config" \
  --value file://fake-data/db-encryption-config.json \
  --type String \
  --overwrite \
  --region "${REGION}"
ok "Encryption config seeded (see_also → /prod/db/monitoring)"

# ---------------------------------------------------------------
# Seed SSM Parameter: /prod/db/monitoring
# ---------------------------------------------------------------
info "Seeding SSM parameter: /prod/db/monitoring ..."
aws ssm put-parameter \
  --name "/prod/db/monitoring" \
  --value file://fake-data/db-monitoring.json \
  --type String \
  --overwrite \
  --region "${REGION}"
ok "Monitoring config seeded (end of chain)"

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Deception Scenario 20 — Deployed${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "  Stack    : ${STACK_NAME}"
echo "  Region   : ${REGION}"
echo "  Role     : infra-params-readonly-role (discovery)"
echo "  SSM Chain:"
echo "    1. /prod/db/primary          → see_also: /prod/db/replica"
echo "    2. /prod/db/replica          → see_also: /prod/db/backup-config"
echo "    3. /prod/db/backup-config    → see_also: /prod/db/encryption-config"
echo "    4. /prod/db/encryption-config → see_also: /prod/db/monitoring"
echo "    5. /prod/db/monitoring       → (end of chain)"
echo -e "${GREEN}=============================================${NC}"
echo ""
ok "Done. All resources are live."
