#!/usr/bin/env bash
#
# deploy.sh — Deploy Deception Scenario 4
#
# This script:
#   1. Lists available VPCs and lets the user pick one
#   2. Lists public subnets in the chosen VPC and lets the user pick one
#   3. Asks for the SSH CIDR to allow (default: 165.225.0.0/24)
#   4. Generates an RSA key pair for the bastion
#   5. Imports it as an EC2 Key Pair
#   6. Deploys the CloudFormation stack into the chosen VPC/subnet
#   7. Stops the EC2 instance (lure stays dormant)
#   8. Uploads the private key to the S3 lure bucket
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - ssh-keygen available
#   - Sufficient IAM permissions for CloudFormation, EC2, S3, IAM
#
set -euo pipefail

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-4"
TEMPLATE_FILE="template.yaml"
KEY_PAIR_NAME="prod-bastion-keypair"
KEY_DIR="keys"
PRIVATE_KEY_FILE="${KEY_DIR}/prod-bastion-keypair.pem"
PUBLIC_KEY_FILE="${KEY_DIR}/prod-bastion-keypair.pub"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
DEFAULT_SSH_CIDR="165.225.0.0/24"

# ---------------------------------------------------------------
# Resolve the AWS Account ID
# ---------------------------------------------------------------
echo "[*] Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "[+] Account ID: ${ACCOUNT_ID}"

BUCKET_NAME="devops-deploy-keys-${ACCOUNT_ID}"

# ---------------------------------------------------------------
# List VPCs and let the user pick
# ---------------------------------------------------------------
echo ""
echo "[*] Available VPCs in ${REGION}:"
echo "-------------------------------------------"

VPC_DATA=$(aws ec2 describe-vpcs \
  --region "${REGION}" \
  --query "Vpcs[*].[VpcId, CidrBlock, Tags[?Key=='Name'].Value | [0] || 'unnamed']" \
  --output text)

if [ -z "${VPC_DATA}" ]; then
  echo "[!] No VPCs found in ${REGION}. Exiting."
  exit 1
fi

INDEX=1
declare -a VPC_IDS=()
while IFS=$'\t' read -r vpc_id cidr name; do
  printf "  %d) %-25s %-18s %s\n" "${INDEX}" "${vpc_id}" "${cidr}" "${name}"
  VPC_IDS+=("${vpc_id}")
  INDEX=$((INDEX + 1))
done <<< "${VPC_DATA}"

echo ""
read -rp "Select VPC number [1]: " VPC_CHOICE
VPC_CHOICE=${VPC_CHOICE:-1}
SELECTED_VPC="${VPC_IDS[$((VPC_CHOICE - 1))]}"
echo "[+] Selected VPC: ${SELECTED_VPC}"

# ---------------------------------------------------------------
# List public subnets in the chosen VPC and let the user pick
# ---------------------------------------------------------------
echo ""
echo "[*] Available subnets in ${SELECTED_VPC}:"
echo "-------------------------------------------"

SUBNET_DATA=$(aws ec2 describe-subnets \
  --region "${REGION}" \
  --filters "Name=vpc-id,Values=${SELECTED_VPC}" \
  --query "Subnets[*].[SubnetId, CidrBlock, AvailabilityZone, MapPublicIpOnLaunch, Tags[?Key=='Name'].Value | [0] || 'unnamed']" \
  --output text)

if [ -z "${SUBNET_DATA}" ]; then
  echo "[!] No subnets found in ${SELECTED_VPC}. Exiting."
  exit 1
fi

INDEX=1
declare -a SUBNET_IDS=()
while IFS=$'\t' read -r subnet_id cidr az public name; do
  pub_label="private"
  if [ "${public}" = "True" ] || [ "${public}" = "true" ]; then
    pub_label="public"
  fi
  printf "  %d) %-27s %-18s %-14s %-8s %s\n" "${INDEX}" "${subnet_id}" "${cidr}" "${az}" "${pub_label}" "${name}"
  SUBNET_IDS+=("${subnet_id}")
  INDEX=$((INDEX + 1))
done <<< "${SUBNET_DATA}"

echo ""
read -rp "Select subnet number [1]: " SUBNET_CHOICE
SUBNET_CHOICE=${SUBNET_CHOICE:-1}
SELECTED_SUBNET="${SUBNET_IDS[$((SUBNET_CHOICE - 1))]}"
echo "[+] Selected subnet: ${SELECTED_SUBNET}"

# ---------------------------------------------------------------
# Ask for SSH CIDR
# ---------------------------------------------------------------
echo ""
read -rp "SSH allowed CIDR [${DEFAULT_SSH_CIDR}]: " SSH_CIDR
SSH_CIDR=${SSH_CIDR:-${DEFAULT_SSH_CIDR}}
echo "[+] SSH CIDR: ${SSH_CIDR}"

# ---------------------------------------------------------------
# Resolve AMI ID
# ---------------------------------------------------------------
DEFAULT_AMI="ami-072cdf002809ade8c"
echo ""
echo "[*] Default AMI: ${DEFAULT_AMI}"

# Try to resolve the AMI name for confirmation
AMI_NAME=$(aws ec2 describe-images \
  --image-ids "${DEFAULT_AMI}" \
  --region "${REGION}" \
  --query "Images[0].Name" \
  --output text 2>/dev/null || echo "unknown")
echo "[+] AMI Name: ${AMI_NAME}"

read -rp "Use this AMI? [Y/n] or enter a different AMI ID: " AMI_CHOICE
if [ -z "${AMI_CHOICE}" ] || [ "${AMI_CHOICE}" = "Y" ] || [ "${AMI_CHOICE}" = "y" ]; then
  AMI_ID="${DEFAULT_AMI}"
else
  AMI_ID="${AMI_CHOICE}"
fi
echo "[+] Using AMI: ${AMI_ID}"

# ---------------------------------------------------------------
# Generate SSH key pair
# ---------------------------------------------------------------
echo ""
echo "[*] Generating RSA key pair..."
mkdir -p "${KEY_DIR}"
rm -f "${PRIVATE_KEY_FILE}" "${PUBLIC_KEY_FILE}"
ssh-keygen -t rsa -b 4096 -f "${PRIVATE_KEY_FILE}" -N "" -q
mv "${PRIVATE_KEY_FILE}.pub" "${PUBLIC_KEY_FILE}"
chmod 600 "${PRIVATE_KEY_FILE}"
echo "[+] Key pair generated: ${PRIVATE_KEY_FILE}"

# ---------------------------------------------------------------
# Import the public key as an EC2 Key Pair
# ---------------------------------------------------------------
echo "[*] Importing EC2 Key Pair: ${KEY_PAIR_NAME} ..."
aws ec2 delete-key-pair \
  --key-name "${KEY_PAIR_NAME}" \
  --region "${REGION}" 2>/dev/null || true

aws ec2 import-key-pair \
  --key-name "${KEY_PAIR_NAME}" \
  --public-key-material fileb://"${PUBLIC_KEY_FILE}" \
  --region "${REGION}"
echo "[+] EC2 Key Pair imported."

# ---------------------------------------------------------------
# Deploy the CloudFormation stack
# ---------------------------------------------------------------
echo "[*] Deploying CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides \
      AccountId="${ACCOUNT_ID}" \
      KeyPairName="${KEY_PAIR_NAME}" \
      VpcId="${SELECTED_VPC}" \
      SubnetId="${SELECTED_SUBNET}" \
      AllowedSshCidr="${SSH_CIDR}" \
      AmiId="${AMI_ID}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

echo "[+] Stack deployed successfully."

# ---------------------------------------------------------------
# Get the instance ID from stack outputs
# ---------------------------------------------------------------
INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" \
  --output text)
echo "[+] Bastion Instance ID: ${INSTANCE_ID}"

# ---------------------------------------------------------------
# Stop the instance (lure stays dormant)
# ---------------------------------------------------------------
echo "[*] Stopping bastion instance (lure stays dormant)..."
aws ec2 stop-instances \
  --instance-ids "${INSTANCE_ID}" \
  --region "${REGION}" > /dev/null

aws ec2 wait instance-stopped \
  --instance-ids "${INSTANCE_ID}" \
  --region "${REGION}"
echo "[+] Instance stopped."

# ---------------------------------------------------------------
# Upload the private key to the S3 lure bucket
# ---------------------------------------------------------------
echo "[*] Uploading SSH private key to s3://${BUCKET_NAME}/keys/prod-bastion-keypair.pem ..."
aws s3 cp "${PRIVATE_KEY_FILE}" \
  "s3://${BUCKET_NAME}/keys/prod-bastion-keypair.pem" \
  --region "${REGION}"
echo "[+] Private key uploaded."

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
SG_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='SecurityGroupId'].OutputValue" \
  --output text)

echo ""
echo "============================================="
echo "  Deception Scenario 4 — Deployed"
echo "============================================="
echo "  Stack      : ${STACK_NAME}"
echo "  Region     : ${REGION}"
echo "  VPC        : ${SELECTED_VPC}"
echo "  Subnet     : ${SELECTED_SUBNET}"
echo "  Role       : devops-s3-deploy-role"
echo "  Bucket     : ${BUCKET_NAME}"
echo "  SSH Key    : s3://${BUCKET_NAME}/keys/prod-bastion-keypair.pem"
echo "  Instance   : ${INSTANCE_ID} (STOPPED)"
echo "  SG         : ${SG_ID} (SSH from ${SSH_CIDR})"
echo "============================================="
echo ""
echo "[*] Instance is stopped. Attacker must:"
echo "    1. Modify SG to allow their IP (AuthorizeSecurityGroupIngress)"
echo "    2. Start the instance (StartInstances)"
echo "    3. SSH in with the key from S3"
echo "[*] Each step generates CloudTrail detection signals."
echo "[*] Done. All resources are live."
