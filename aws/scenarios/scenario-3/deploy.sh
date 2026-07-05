#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 3 and seed SSM Parameter Store with fake data
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
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-3"
TEMPLATE_FILE="template.yaml"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID automatically
# ---------------------------------------------------------------
echo "[*] Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "[+] Account ID: ${ACCOUNT_ID}"

# ---------------------------------------------------------------
# Deploy the CloudFormation stack
# ---------------------------------------------------------------
echo "[*] Deploying CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides AccountId="${ACCOUNT_ID}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

echo "[+] Stack deployed successfully."

# ---------------------------------------------------------------
# Wait for stack to stabilize
# ---------------------------------------------------------------
echo "[*] Waiting for stack to stabilize..."
aws cloudformation wait stack-create-complete \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" 2>/dev/null || true

# ---------------------------------------------------------------
# Seed Parameter 1: RDS master credentials
# ---------------------------------------------------------------
echo "[*] Updating parameter: /prod/database/master-credentials ..."
aws ssm put-parameter \
  --name "/prod/database/master-credentials" \
  --type "SecureString" \
  --value "$(cat fake-data/database-master-credentials.json)" \
  --overwrite \
  --region "${REGION}"
echo "[+] Database master credentials seeded."

# ---------------------------------------------------------------
# Seed Parameter 2: GitHub deploy token
# ---------------------------------------------------------------
echo "[*] Updating parameter: /prod/ci-cd/github-deploy-token ..."
aws ssm put-parameter \
  --name "/prod/ci-cd/github-deploy-token" \
  --type "SecureString" \
  --value "$(cat fake-data/github-deploy-token.json)" \
  --overwrite \
  --region "${REGION}"
echo "[+] GitHub deploy token seeded."

# ---------------------------------------------------------------
# Seed Parameter 3: Datadog API keys
# ---------------------------------------------------------------
echo "[*] Updating parameter: /prod/monitoring/datadog-api-keys ..."
aws ssm put-parameter \
  --name "/prod/monitoring/datadog-api-keys" \
  --type "SecureString" \
  --value "$(cat fake-data/datadog-api-keys.json)" \
  --overwrite \
  --region "${REGION}"
echo "[+] Datadog API keys seeded."

# ---------------------------------------------------------------
# Seed Parameter 4: VPN admin credentials
# ---------------------------------------------------------------
echo "[*] Updating parameter: /prod/vpn/admin-credentials ..."
aws ssm put-parameter \
  --name "/prod/vpn/admin-credentials" \
  --type "SecureString" \
  --value "$(cat fake-data/vpn-admin-credentials.json)" \
  --overwrite \
  --region "${REGION}"
echo "[+] VPN admin credentials seeded."

# ---------------------------------------------------------------
# Seed Parameter 5: EKS kubeconfig
# The kubeconfig is YAML, so we store it as-is in the parameter
# ---------------------------------------------------------------
echo "[*] Updating parameter: /prod/kubernetes/cluster-admin-kubeconfig ..."
aws ssm put-parameter \
  --name "/prod/kubernetes/cluster-admin-kubeconfig" \
  --type "SecureString" \
  --tier "Advanced" \
  --value "$(cat fake-data/eks-kubeconfig.yaml)" \
  --overwrite \
  --region "${REGION}"
echo "[+] EKS kubeconfig seeded."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "============================================="
echo "  Deception Scenario 3 — Deployed"
echo "============================================="
echo "  Stack      : ${STACK_NAME}"
echo "  Region     : ${REGION}"
echo "  Role       : infra-config-readonly-role"
echo "  Parameters :"
echo "    - /prod/database/master-credentials"
echo "    - /prod/ci-cd/github-deploy-token"
echo "    - /prod/monitoring/datadog-api-keys"
echo "    - /prod/vpn/admin-credentials"
echo "    - /prod/kubernetes/cluster-admin-kubeconfig"
echo "============================================="
echo ""
echo "[*] Done. All resources are live."
