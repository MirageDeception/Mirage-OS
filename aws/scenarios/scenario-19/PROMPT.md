# Scenario 21 — CloudFormation Stack Outputs Lure: Exposed Infrastructure Secrets

## Prompt

Create a deception scenario called `scenario-21` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content.

### Deception Chain Overview

```
Attacker
  │
  ├─► Discovers IAM Role: cfn-audit-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► cloudformation:ListStacks → finds prod-core-infrastructure
  │
  ├─► cloudformation:DescribeStacks → reads stack outputs:
  │     ├─► DatabaseEndpoint: prod-core-db.xxx.us-west-2.rds.amazonaws.com
  │     ├─► DatabasePassword: <plaintext password in output>
  │     ├─► ApiGatewayUrl: https://xxx.execute-api.us-west-2.amazonaws.com/prod
  │     ├─► ApiKey: <plaintext API key in output>
  │     ├─► RedisEndpoint: prod-cache.xxx.usw2.cache.amazonaws.com
  │     ├─► RedisAuthToken: <plaintext auth token>
  │     └─► AdminDashboardUrl: https://admin.prod.internal.corp
  │
  ├─► cloudformation:ListExports → finds cross-stack references
  │     ├─► prod-vpc-id, prod-private-subnet-ids
  │     └─► prod-db-security-group-id
  │
  └─► Attempts to use extracted endpoints/credentials → triggers detection
```

### Lure Resources

- **IAM Role**: Named `cfn-audit-readonly-role`
  - `cloudformation:ListStacks`, `cloudformation:DescribeStacks`
  - `cloudformation:ListExports`, `cloudformation:GetTemplate` — scoped to lure stack
  - Trust: account root principal

- **CloudFormation Stack**: Named `prod-core-infrastructure`
  - A minimal template that creates only SSM parameters (cheap placeholders)
  - But the stack OUTPUTS contain the juicy fake data:
    - `DatabaseEndpoint`, `DatabasePassword`
    - `ApiGatewayUrl`, `ApiKey`
    - `RedisEndpoint`, `RedisAuthToken`
    - `AdminDashboardUrl`
  - Stack exports cross-stack references with enticing names

### Key Design Point

The lure is in the CloudFormation stack outputs and exports — not in the resources
themselves. The stack creates minimal resources (a couple of SSM parameters) but
exposes secrets in its outputs, which is a common real-world misconfiguration.

### Additional Requirements

- [ ] Cost: $0.00/month (CloudFormation + SSM Standard = free)
- [ ] Stack outputs must contain realistic-looking credentials in plaintext
- [ ] Stack exports should reference realistic VPC/subnet/security-group names
- [ ] Include `deploy.sh`, `README.md`
- [ ] Default region: us-west-2

### Output Structure

```
scenarios/scenario-21/
├── template.yaml
├── deploy.sh
└── README.md
```
