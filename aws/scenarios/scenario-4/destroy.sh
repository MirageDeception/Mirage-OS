#!/usr/bin/env bash
#
# destroy.sh — Tear down Deception Scenario 4
#
# This script cleans up all resources created by deploy.sh:
#   1. Empties the S3 bucket (required before CloudFormation can delete it)
#   2. Deletes the CloudFormation stack
#   3. Deletes the EC2 Key Pair
#   4. Removes locally generated key files
#
# Usage:
#   chmod +x destroy.sh
#   ./destroy.sh
#
set -euo pipefail

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
STACK_NAME="deception-scenario-4"
KEY_PAIR_NAME="prod-bastion-keypair"
KEY_DIR="keys"
REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# ---------------------------------------------------------------
# Resolve the AWS Account ID
# ---------------------------------------------------------------
echo "[*] Resolving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "[+] Account ID: ${ACCOUNT_ID}"

BUCKET_NAME="devops-deploy-keys-${ACCOUNT_ID}"

# ---------------------------------------------------------------
# Empty the S3 bucket (CloudFormation cannot delete non-empty buckets)
# ---------------------------------------------------------------
echo "[*] Emptying S3 bucket: ${BUCKET_NAME} ..."
aws s3 rm "s3://${BUCKET_NAME}" \
  --recursive \
  --region "${REGION}" 2>/dev/null || echo "[!] Bucket already empty or does not exist"

# Delete all object versions (bucket has versioning enabled)
echo "[*] Removing all object versions..."
VERSIONS=$(aws s3api list-object-versions \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --query "{Objects: Versions[].{Key:Key,VersionId:VersionId}}" \
  --output json 2>/dev/null || echo '{"Objects": null}')

if [ "$(echo "${VERSIONS}" | jq -r '.Objects')" != "null" ]; then
  echo "${VERSIONS}" | jq '{Objects: .Objects, Quiet: true}' > /tmp/delete-markers.json
  aws s3api delete-objects \
    --bucket "${BUCKET_NAME}" \
    --delete file:///tmp/delete-markers.json \
    --region "${REGION}" > /dev/null
  rm -f /tmp/delete-markers.json
  echo "[+] Object versions deleted"
fi

# Delete any delete markers
DELETE_MARKERS=$(aws s3api list-object-versions \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --query "{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}" \
  --output json 2>/dev/null || echo '{"Objects": null}')

if [ "$(echo "${DELETE_MARKERS}" | jq -r '.Objects')" != "null" ]; then
  echo "${DELETE_MARKERS}" | jq '{Objects: .Objects, Quiet: true}' > /tmp/delete-markers.json
  aws s3api delete-objects \
    --bucket "${BUCKET_NAME}" \
    --delete file:///tmp/delete-markers.json \
    --region "${REGION}" > /dev/null
  rm -f /tmp/delete-markers.json
  echo "[+] Delete markers removed"
fi

echo "[+] Bucket emptied"

# ---------------------------------------------------------------
# Delete the CloudFormation stack
# ---------------------------------------------------------------
echo "[*] Deleting CloudFormation stack: ${STACK_NAME} ..."
aws cloudformation delete-stack \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}"

echo "[*] Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}"
echo "[+] Stack deleted"

# ---------------------------------------------------------------
# Delete the EC2 Key Pair
# ---------------------------------------------------------------
echo "[*] Deleting EC2 Key Pair: ${KEY_PAIR_NAME} ..."
aws ec2 delete-key-pair \
  --key-name "${KEY_PAIR_NAME}" \
  --region "${REGION}" 2>/dev/null || true
echo "[+] Key pair deleted"

# ---------------------------------------------------------------
# Remove local key files
# ---------------------------------------------------------------
echo "[*] Removing local key files..."
rm -f "${KEY_DIR}/prod-bastion-keypair.pem" "${KEY_DIR}/prod-bastion-keypair.pub"
rmdir "${KEY_DIR}" 2>/dev/null || true
echo "[+] Local files cleaned up"

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "============================================="
echo "  Deception Scenario 4 — Destroyed"
echo "============================================="
echo "  Stack      : ${STACK_NAME} (deleted)"
echo "  Bucket     : ${BUCKET_NAME} (emptied + deleted)"
echo "  Key Pair   : ${KEY_PAIR_NAME} (deleted)"
echo "  Local keys : ${KEY_DIR}/ (removed)"
echo "============================================="
echo ""
echo "[+] All resources cleaned up."
