# Scenario 3 — SSM Parameter Store Lure: Infrastructure Credentials Vault

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`infra-config-readonly-role` — assumable by any principal in the account.
The role grants the ability to describe all SSM parameters and read values
under the `/prod/*` path.

The attacker enumerates parameters and finds what appears to be a treasure
trove of production infrastructure credentials:

- RDS MySQL master credentials with connection endpoint
- GitHub personal access token with repo/workflow scope for the platform monorepo
- Datadog API and application keys for production monitoring
- VPN admin console credentials with MFA seed
- EKS cluster-admin kubeconfig with a bearer token

All values look legitimate and immediately usable. The realistic naming,
parameter hierarchy, and credential formats are designed to lure the attacker
into attempting to use them — triggering detection alerts.

## Resource Chain

```
Attacker
  │
  ├─► Discovers IAM Role: infra-config-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains ssm:DescribeParameters + scoped Get access
  │
  ├─► Describes parameters ─► finds /prod/* parameter hierarchy
  │
  └─► Reads parameter values
        │
        ├─► /prod/database/master-credentials
        │     └─► RDS host, master username, master password
        │
        ├─► /prod/ci-cd/github-deploy-token
        │     └─► GitHub PAT, org, repo scope, deploy key fingerprint
        │
        ├─► /prod/monitoring/datadog-api-keys
        │     └─► Datadog API key, app key, site
        │
        ├─► /prod/vpn/admin-credentials
        │     └─► VPN endpoint, admin username/password, MFA seed
        │
        └─► /prod/kubernetes/cluster-admin-kubeconfig
              └─► EKS cluster endpoint, CA cert, cluster-admin bearer token
```

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — IAM role + 5 SSM parameters |
| `deploy.sh` | One-command deploy script — creates the stack and seeds all parameter values |
| `fake-data/database-master-credentials.json` | Fake RDS master credentials |
| `fake-data/github-deploy-token.json` | Fake GitHub PAT and deploy key |
| `fake-data/datadog-api-keys.json` | Fake Datadog API and app keys |
| `fake-data/vpn-admin-credentials.json` | Fake VPN admin console credentials |
| `fake-data/eks-kubeconfig.yaml` | Fake EKS cluster-admin kubeconfig |

## Security Best Practices Applied

- All parameters use SecureString type (encrypted with `aws/ssm` KMS key) via deploy script
- IAM role `GetParameter` and `GetParameters` scoped to the five specific parameter ARNs
- `GetParametersByPath` scoped to `/prod/*` path only
- `DescribeParameters` is the only broad permission (required for discovery — part of the lure)
- IAM role session duration capped at 1 hour
- Trust policy scoped to account root principal only
- EKS kubeconfig stored as Advanced tier (supports larger payloads)

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
  --stack-name deception-scenario-3 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM

# Seed each parameter as SecureString
aws ssm put-parameter --name "/prod/database/master-credentials" \
  --type SecureString --value "$(cat fake-data/database-master-credentials.json)" --overwrite

aws ssm put-parameter --name "/prod/ci-cd/github-deploy-token" \
  --type SecureString --value "$(cat fake-data/github-deploy-token.json)" --overwrite

aws ssm put-parameter --name "/prod/monitoring/datadog-api-keys" \
  --type SecureString --value "$(cat fake-data/datadog-api-keys.json)" --overwrite

aws ssm put-parameter --name "/prod/vpn/admin-credentials" \
  --type SecureString --value "$(cat fake-data/vpn-admin-credentials.json)" --overwrite

aws ssm put-parameter --name "/prod/kubernetes/cluster-admin-kubeconfig" \
  --type SecureString --tier Advanced --value "$(cat fake-data/eks-kubeconfig.yaml)" --overwrite
```

## Customization

Edit the files in `fake-data/` to replace credentials with your own values.
Keep the formats realistic — match real provider patterns (e.g., `ghp_` prefix
for GitHub PATs, base64-encoded CA data for kubeconfigs).
