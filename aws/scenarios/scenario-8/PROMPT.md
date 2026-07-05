# Scenario 9 — IAM Role Chain Loop: Circular Role Assumption

## Prompt

Create a deception scenario called `scenario-9` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers role-a: prod-microservice-auth-role
  │     └─► Can sts:AssumeRole → prod-microservice-data-role
  │
  ├─► Assumes role-b: prod-microservice-data-role
  │     └─► Can sts:AssumeRole → prod-microservice-admin-role
  │
  ├─► Assumes role-c: prod-microservice-admin-role
  │     └─► Can sts:AssumeRole → prod-microservice-auth-role (back to start)
  │
  └─► Each role has read access to a different empty/minimal resource
      generating CloudTrail events at every hop
```

### Lure Resources

- **IAM Role A**: Named `prod-microservice-auth-role`
  - Trust: account root principal
  - Permissions: `sts:AssumeRole` on Role B, `ssm:GetParameter` on `/prod/auth/oidc-config`
  - Tags: `Environment=production`, `Project=microservices`, `Service=auth`

- **IAM Role B**: Named `prod-microservice-data-role`
  - Trust: account root principal
  - Permissions: `sts:AssumeRole` on Role C, `ssm:GetParameter` on `/prod/data/lake-credentials`
  - Tags: `Environment=production`, `Project=microservices`, `Service=data-layer`

- **IAM Role C**: Named `prod-microservice-admin-role`
  - Trust: account root principal
  - Permissions: `sts:AssumeRole` on Role A, `ssm:GetParameter` on `/prod/admin/console-credentials`
  - Tags: `Environment=production`, `Project=microservices`, `Service=admin`

- **SSM Parameter 1**: `/prod/auth/oidc-config` — fake OIDC provider config with client secrets
- **SSM Parameter 2**: `/prod/data/lake-credentials` — fake data lake access credentials
- **SSM Parameter 3**: `/prod/admin/console-credentials` — fake admin console credentials

### Additional Requirements

- [ ] Each role can assume the next in the chain, forming a loop
- [ ] Each role also has one SSM parameter with themed fake credentials
- [ ] Include `deploy.sh`, `README.md`
- [ ] Cost: $0.00/month (IAM + SSM Standard = free)
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-9/
├── template.yaml
├── deploy.sh
├── fake-data/
│   ├── oidc-config.json
│   ├── lake-credentials.json
│   └── console-credentials.json
└── README.md
```
