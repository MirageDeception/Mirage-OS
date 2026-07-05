#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 18 (Resource Tags Breadcrumb Trail)
#
# This script walks through the attack chain step by step with colored output.
# The attacker assumes the discovery role, enumerates resource tags, and follows
# the breadcrumb trail to discover additional resource ARNs and S3 URIs.
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
echo "  SCENARIO 18 — ABUSE CHAIN"
echo "  Resource Tags Breadcrumb Trail"
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
step "2" "Assuming discovery role: resource-inventory-readonly-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/resource-inventory-readonly-role"
attack "sts:AssumeRole → ${ROLE_ARN}"

CREDS=$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "recon-inventory-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "${CREDS}" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "${CREDS}" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "${CREDS}" | jq -r .SessionToken)
info "Role assumed successfully"

# ---------------------------------------------------------------
step "3" "Enumerating tag keys across the account"
# ---------------------------------------------------------------
attack "tag:GetTagKeys"
echo ""
echo -e "${YELLOW}--- Tag Keys Found ---${NC}"
aws resourcegroupstaggingapi get-tag-keys --query "TagKeys" --output table
echo ""

# ---------------------------------------------------------------
step "4" "Searching for resources with breadcrumb tags (ConfigBackup, SecretsRef, RelatedRole)"
# ---------------------------------------------------------------
attack "tag:GetResources (filter: ConfigBackup)"
echo ""
echo -e "${YELLOW}--- Resources tagged with ConfigBackup ---${NC}"
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=ConfigBackup \
  --query "ResourceTagMappingList[].{ARN:ResourceARN,Tags:Tags}" \
  --output json | jq '.'
echo ""

attack "tag:GetResources (filter: RelatedRole)"
echo ""
echo -e "${YELLOW}--- Resources tagged with RelatedRole ---${NC}"
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=RelatedRole \
  --query "ResourceTagMappingList[].{ARN:ResourceARN,Tags:Tags}" \
  --output json | jq '.'
echo ""

attack "tag:GetResources (filter: BackupBucket)"
echo ""
echo -e "${YELLOW}--- Resources tagged with BackupBucket ---${NC}"
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=BackupBucket \
  --query "ResourceTagMappingList[].{ARN:ResourceARN,Tags:Tags}" \
  --output json | jq '.'
echo ""

# ---------------------------------------------------------------
step "5" "Reading tags on prod-backup-automation-role"
# ---------------------------------------------------------------
attack "iam:ListRoleTags → prod-backup-automation-role"
echo ""
echo -e "${YELLOW}--- Tags on prod-backup-automation-role ---${NC}"
aws iam list-role-tags \
  --role-name prod-backup-automation-role \
  --query "Tags" \
  --output table
echo ""

# ---------------------------------------------------------------
step "6" "Reading tags on SSM parameter /prod/inventory/service-registry"
# ---------------------------------------------------------------
attack "ssm:ListTagsForResource → /prod/inventory/service-registry"
echo ""
echo -e "${YELLOW}--- Tags on /prod/inventory/service-registry ---${NC}"
aws ssm list-tags-for-resource \
  --resource-type Parameter \
  --resource-id "/prod/inventory/service-registry" \
  --query "TagList" \
  --output table
echo ""

# ---------------------------------------------------------------
step "7" "Following breadcrumbs — attempting to access referenced resources"
# ---------------------------------------------------------------
warn "Breadcrumbs discovered:"
echo "  • s3://prod-config-backup-vault/iam-export.json"
echo "  • arn:aws:secretsmanager:us-west-2:${ACCOUNT_ID}:secret:prod/master-api-keys"
echo "  • alias/prod-master-encryption"
echo "  • arn:aws:iam::${ACCOUNT_ID}:role/prod-data-admin-role"
echo "  • s3://prod-dynamodb-backups/customer-data/"
echo "  • arn:aws:cloudwatch::${ACCOUNT_ID}:dashboard/prod-service-health"
echo ""
warn "Each lookup attempt generates additional CloudTrail events"
warn "Referenced resources may or may not exist — the trail is the lure"

# ---------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------
echo ""
step "8" "Cleaning up session"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
info "Session credentials cleared"

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: AssumeRole on resource-inventory-readonly-role"
echo "  • CloudTrail: GetTagKeys"
echo "  • CloudTrail: GetResources (×3 tag filter queries)"
echo "  • CloudTrail: ListRoleTags on prod-backup-automation-role"
echo "  • CloudTrail: ListTagsForResource on /prod/inventory/service-registry"
echo ""
echo -e "${YELLOW}Total CloudTrail events: 7+${NC}"
echo ""
