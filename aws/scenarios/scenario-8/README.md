# Scenario 9 — IAM Role Chain Loop: Circular Role Assumption

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`prod-microservice-auth-role` — assumable by any principal in the account. The
role grants permission to assume a second role and read an SSM parameter
containing what appears to be OIDC provider configuration with client secrets.

Following the assumption chain, the attacker assumes `prod-microservice-data-role`,
which grants access to a different SSM parameter with data lake credentials and
permission to assume a third role. The third role, `prod-microservice-admin-role`,
provides admin console credentials via SSM and permission to assume the first
role — completing the loop.

The three roles form a circular chain (A→B→C→A). Each hop generates CloudTrail
events for `AssumeRole` and `GetParameter`, giving defenders multiple detection
opportunities while the attacker chases credentials that lead nowhere.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role A: prod-microservice-auth-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes Role A
  │     ├─► ssm:GetParameter → /prod/auth/oidc-config
  │     │     └─► OIDC provider config with client secrets
  │     └─► sts:AssumeRole → prod-microservice-data-role
  │
  ├─► Assumes Role B: prod-microservice-data-role
  │     ├─► ssm:GetParameter → /prod/data/lake-credentials
  │     │     └─► Data lake access credentials (Redshift, Glue, S3)
  │     └─► sts:AssumeRole → prod-microservice-admin-role
  │
  ├─► Assumes Role C: prod-microservice-admin-role
  │     ├─► ssm:GetParameter → /prod/admin/console-credentials
  │     │     └─► Admin console credentials and service accounts
  │     └─► sts:AssumeRole → prod-microservice-auth-role (back to start)
  │
  └─► Attacker is trapped in a loop — every hop triggers CloudTrail alerts
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Role A (auth) | IAM Role | `prod-microservice-auth-role` |
| Role B (data) | IAM Role | `prod-microservice-data-role` |
| Role C (admin) | IAM Role | `prod-microservice-admin-role` |
| OIDC Config | SSM Parameter | `/prod/auth/oidc-config` |
| Lake Credentials | SSM Parameter | `/prod/data/lake-credentials` |
| Console Credentials | SSM Parameter | `/prod/admin/console-credentials` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — 3 IAM roles in circular chain + 3 SSM parameters |
| `deploy.sh` | One-command deploy script — creates the stack and seeds all SSM parameters |
| `fake-data/oidc-config.json` | Fake OIDC provider configuration with client secrets |
| `fake-data/lake-credentials.json` | Fake data lake access credentials (Redshift, Glue, S3, Athena) |
| `fake-data/console-credentials.json` | Fake admin console credentials and service accounts |

## Security Best Practices Applied

- All three IAM roles: trust policy scoped to account root principal only (no public access)
- Each role's permissions scoped to specific resource ARNs (least privilege)
- Role A can only assume Role B, Role B can only assume Role C, Role C can only assume Role A
- SSM parameters use Standard tier (no additional cost)
- No public endpoints, no Lambda functions, no S3 buckets exposed
- Every action in the chain generates CloudTrail events for detection

## Cost

$0.00/month — IAM roles and SSM Standard parameters are free.

## Deployment

### Quick deploy (recommended)

```bash
chmod +x deploy.sh
./deploy.sh
```

Override region:

```bash
AWS_DEFAULT_REGION=eu-west-1 ./deploy.sh
```

### Manual deploy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name deception-scenario-9 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset

aws ssm put-parameter \
  --name /prod/auth/oidc-config \
  --value file://fake-data/oidc-config.json \
  --type String \
  --overwrite

aws ssm put-parameter \
  --name /prod/data/lake-credentials \
  --value file://fake-data/lake-credentials.json \
  --type String \
  --overwrite

aws ssm put-parameter \
  --name /prod/admin/console-credentials \
  --value file://fake-data/console-credentials.json \
  --type String \
  --overwrite
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-9 --region us-west-2
```
