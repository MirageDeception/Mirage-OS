#!/usr/bin/env bash
#
# cleanup.sh — Reset Scenario 4 after an abuse run
#
# This script reverses the attacker's actions:
#   1. Stops the bastion instance (if running)
#   2. Removes any attacker-added SSH ingress rules from the security group
#      (keeps only the original AllowedSshCidr rule)
#
# After running this, the scenario is ready for another abuse.sh run.
#
# Usage:
#   chmod +x cleanup.sh
#   ./cleanup.sh
#
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
STACK_NAME="deception-scenario-4"

# ---------------------------------------------------------------
# Colors
# ---------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "  ${GREEN}[+]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
step() { echo -e "\n${CYAN}[STEP $1]${NC} $2"; }

echo ""
echo "============================================="
echo "  Scenario 4 — Post-Abuse Cleanup"
echo "============================================="

# ---------------------------------------------------------------
step "1" "Resolving stack resources"
# ---------------------------------------------------------------
INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" \
  --output text)

SG_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='SecurityGroupId'].OutputValue" \
  --output text)

info "Instance: ${INSTANCE_ID}"
info "Security Group: ${SG_ID}"

# ---------------------------------------------------------------
step "2" "Stopping bastion instance (if running)"
# ---------------------------------------------------------------
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --region "${REGION}" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text)

if [ "${INSTANCE_STATE}" = "running" ]; then
  aws ec2 stop-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${REGION}" > /dev/null
  info "Stopping instance..."
  aws ec2 wait instance-stopped \
    --instance-ids "${INSTANCE_ID}" \
    --region "${REGION}"
  info "Instance stopped"
elif [ "${INSTANCE_STATE}" = "stopped" ]; then
  info "Instance already stopped"
else
  warn "Instance in state: ${INSTANCE_STATE} — skipping"
fi

# ---------------------------------------------------------------
step "3" "Removing attacker-added security group rules"
# ---------------------------------------------------------------
# Get the original CIDR from the stack parameters
ORIGINAL_CIDR=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Parameters[?ParameterKey=='AllowedSshCidr'].ParameterValue" \
  --output text)

info "Original allowed CIDR: ${ORIGINAL_CIDR}"

# Get all current SSH ingress rules
INGRESS_CIDRS=$(aws ec2 describe-security-groups \
  --group-ids "${SG_ID}" \
  --region "${REGION}" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\`].IpRanges[*].CidrIp" \
  --output text)

REMOVED=0
for cidr in ${INGRESS_CIDRS}; do
  if [ "${cidr}" != "${ORIGINAL_CIDR}" ]; then
    aws ec2 revoke-security-group-ingress \
      --group-id "${SG_ID}" \
      --protocol tcp \
      --port 22 \
      --cidr "${cidr}" \
      --region "${REGION}" > /dev/null
    info "Removed SSH rule: ${cidr}"
    REMOVED=$((REMOVED + 1))
  fi
done

if [ ${REMOVED} -eq 0 ]; then
  info "No attacker rules found — SG already clean"
else
  info "Removed ${REMOVED} attacker-added rule(s)"
fi

# ---------------------------------------------------------------
step "4" "Cleanup complete"
# ---------------------------------------------------------------
echo ""
echo "============================================="
echo "  Scenario 4 — Reset Complete"
echo "============================================="
echo "  Instance : ${INSTANCE_ID} (STOPPED)"
echo "  SG       : ${SG_ID} (SSH from ${ORIGINAL_CIDR} only)"
echo "============================================="
echo ""
echo "[+] Ready for next abuse.sh run."
