# Scenario 21 — CloudFormation Stack Outputs Lure: Exposed Infrastructure Secrets

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`cfn-audit-readonly-role` — assumable by any principal in the account. The role
grants read-only access to CloudFormation stack metadata, outputs, and exports.

The attacker lists CloudFormation stacks and finds one named
`prod-core-infrastructure` — a name that suggests it manages critical production
resources. Describing the stack reveals outputs containing plaintext credentials:

- RDS database endpoint and master password
- API Gateway URL and API key
- ElastiCache Redis endpoint and AUTH token
- Admin dashboard URL

The stack also creates cross-stack exports with enticing names like `prod-vpc-id`,
`prod-private-subnet-ids`, and `prod-db-security-group-id` — giving the attacker
network topology information for lateral movement planning.

This mimics a common real-world misconfiguration where sensitive values are
accidentally exposed in CloudFormation outputs. The stack itself creates only
minimal resources (SSM parameters), but the outputs are the lure.

## Deception Chain

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
  ├─► cloudformation:ListExports → finds cross-stack references:
  │     ├─► prod-vpc-id, prod-private-subnet-ids
  │     ├─► prod-db-security-group-id
  │     ├─► prod-database-endpoint, prod-api-gateway-url
  │     └─► prod-redis-endpoint
  │
  ├─► cloudformation:GetTemplate → reads full template source
  │
  └─► Attempts to use extracted endpoints/credentials → triggers detection
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `cfn-audit-readonly-role` |
| Endpoints Config | SSM Parameter | `/prod/core-infra/endpoints` |
| Secrets Reference | SSM Parameter | `/prod/core-infra/secrets-ref` |

## Stack Outputs (The Lure)

| Output Key | Description | Contains |
|------------|-------------|----------|
| `DatabaseEndpoint` | RDS endpoint | Realistic hostname |
| `DatabasePassword` | DB master password | Plaintext credential |
| `ApiGatewayUrl` | API Gateway URL | Realistic endpoint |
| `ApiKey` | API Gateway key | Plaintext credential |
| `RedisEndpoint` | ElastiCache endpoint | Realistic hostname |
| `RedisAuthToken` | Redis AUTH token | Plaintext credential |
| `AdminDashboardUrl` | Admin panel URL | Internal hostname |

## Cross-Stack Exports

| Export Name | Value |
|-------------|-------|
| `prod-database-endpoint` | RDS hostname |
| `prod-api-gateway-url` | API Gateway URL |
| `prod-redis-endpoint` | ElastiCache hostname |
| `prod-vpc-id` | VPC ID |
| `prod-private-subnet-ids` | Subnet IDs |
| `prod-db-security-group-id` | Security group ID |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — IAM role + SSM parameters + exposed outputs |
| `deploy.sh` | One-command deploy script — creates the stack |
| `abuse.sh` | Simulates the attacker abuse chain — lists stacks, reads outputs, enumerates exports |

## Security Best Practices Applied

- IAM discovery role: trust policy scoped to account root principal (not public)
- Stack creates only SSM Standard parameters (minimal resources)
- No actual databases, caches, or API gateways are created
- All credentials in outputs are honeytokens — not connected to real services
- SSM parameters use Standard tier ($0.00/month)

## Key Design Point

The lure is in the CloudFormation stack outputs and exports — not in the
resources themselves. The stack creates minimal resources (SSM parameters) but
exposes secrets in its outputs, which is a common real-world misconfiguration.
The stack name `prod-core-infrastructure` is deliberately chosen to look like
a high-value target.

## Cost

$0.00/month — CloudFormation, IAM roles, and SSM Standard parameters are free.

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
  --stack-name prod-core-infrastructure \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name prod-core-infrastructure --region us-west-2
```
