# Scenario 3 — SSM Parameter Store Lure: Infrastructure Credentials Vault

## Prompt

Create a deception scenario called `scenario-3` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or parameter content. All credentials must look legitimate and usable to
maximize attacker engagement.

### Lure Resources
### Lure Resources

- **IAM Role**: Named `infra-config-readonly-role` with permissions:
  - `ssm:DescribeParameters`
  - `ssm:GetParameter` condition on the specific resource only
  - `ssm:GetParameters` condition on the specific resource only
  - `ssm:GetParametersByPath`
  - `sts:AssumeRole` in trust policy by anyone in this account (root principal)

- **SSM Parameter 1**: Named `/prod/database/master-credentials` (SecureString)
  - Contains fake RDS master username/password and connection endpoint

- **SSM Parameter 2**: Named `/prod/ci-cd/github-deploy-token` (SecureString)
  - Contains fake GitHub personal access token and deploy key for the CI/CD pipeline

- **SSM Parameter 3**: Named `/prod/monitoring/datadog-api-keys` (SecureString)
  - Contains fake Datadog API key and application key

- **SSM Parameter 4**: Named `/prod/vpn/admin-credentials` (SecureString)
  - Contains fake VPN admin console credentials and endpoint

- **SSM Parameter 5**: Named `/prod/kubernetes/cluster-admin-kubeconfig` (SecureString)
  - Contains a fake kubeconfig with expired cluster-admin token for an EKS cluster

### Trust / Access Model

- Role assumable by any principal in this account via `sts:AssumeRole` (root principal in trust policy)
- SSM parameters encrypted with the default AWS-managed KMS key (`aws/ssm`)
- Role policy scoped to `/prod/*` parameter path only (looks like intentional least privilege)

### Fake Data to Seed

- `fake-data/database-master-credentials.json`:
  ```json
  {
    "engine": "mysql",
    "host": "prod-platform-db.c9aksj2e7rzo.us-east-1.rds.amazonaws.com",
    "port": 3306,
    "database": "platform_production",
    "master_username": "root_admin",
    "master_password": "EXPIRED-Rds!M@ster#2024xK9mP2vL5n",
    "ssl_mode": "VERIFY_IDENTITY"
  }
  ```

- `fake-data/github-deploy-token.json`:
  ```json
  {
    "github_pat": "ghp_EXPIRED_1a2B3c4D5e6F7g8H9i0JkLmNoPqRsTuVwX",
    "github_org": "acme-corp-internal",
    "deploy_key_fingerprint": "SHA256:EXPIRED+nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5",
    "repo_scope": "acme-corp-internal/platform-monorepo",
    "permissions": "repo, workflow, packages:read"
  }
  ```

- `fake-data/datadog-api-keys.json`:
  ```json
  {
    "api_key": "EXPIRED_dd_api_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
    "app_key": "EXPIRED_dd_app_f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1a0b9c8d7",
    "site": "datadoghq.com",
    "environment_tag": "env:production"
  }
  ```

- `fake-data/vpn-admin-credentials.json`:
  ```json
  {
    "vpn_endpoint": "https://vpn.prod.internal.corp",
    "admin_console": "https://vpn.prod.internal.corp:8443/admin",
    "admin_username": "vpnadmin",
    "admin_password": "EXPIRED-Vpn@dm1n#Pr0d!2024kL2mN9p",
    "mfa_seed": "EXPIRED-JBSWY3DPEHPK3PXP"
  }
  ```

- `fake-data/eks-kubeconfig.yaml`:
  ```yaml
  apiVersion: v1
  kind: Config
  clusters:
    - cluster:
        server: https://A1B2C3D4E5.gr7.us-east-1.eks.amazonaws.com
        certificate-authority-data: EXPIRED-LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0t...
      name: arn:aws:eks:us-east-1:123456789012:cluster/prod-platform-cluster
  contexts:
    - context:
        cluster: arn:aws:eks:us-east-1:123456789012:cluster/prod-platform-cluster
        user: cluster-admin
        namespace: default
      name: prod-platform-admin
  current-context: prod-platform-admin
  users:
    - name: cluster-admin
      user:
        token: EXPIRED-eyJhbGciOiJSUzI1NiIsImtpZCI6IkZBS0VLRVkifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmUtc3lzdGVtOmNsdXN0ZXItYWRtaW4ifQ.FAKE_SIGNATURE
  ```

### Resource Naming Style

- Parameters follow `/prod/<domain>/<credential-type>` hierarchy
- Role name suggests infrastructure config read access
- Tags: `Environment=production`, `Project=platform-infrastructure`, `ManagedBy=terraform`, `CostCenter=CC-3045`

### Additional Requirements

- [ ] All resources must follow security best practices (SecureString type for all parameters, least privilege IAM)
- [ ] Parameters should have realistic descriptions and tiers
- [ ] Include a `deploy.sh` bash script that deploys the stack and puts all parameter values — with comments
- [ ] Include a `README.md` explaining the deception story, resource chain, file listing, and deployment steps
- [ ] All secrets/credentials must be completely fake placeholder data (use `EXPIRED` prefix)
- [ ] Place everything under `scenarios/scenario-3/`

### Output Structure

```
scenarios/scenario-3/
├── template.yaml
├── deploy.sh
├── fake-data/
│   ├── database-master-credentials.json
│   ├── github-deploy-token.json
│   ├── datadog-api-keys.json
│   ├── vpn-admin-credentials.json
│   └── eks-kubeconfig.yaml
└── README.md
```
