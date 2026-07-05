# Scenario 5 — ECR Lure: Container Image with Fake PII, Credentials & ASIA Token

## Deception Story

This scenario deploys an ECR repository named `prod-payment-service` containing
a Docker image that looks like a production payment microservice. The image has
secrets baked into its filesystem: database credentials, Stripe API keys, PII
records, internal API endpoints, and AWS session credentials.

When combined with scenario-4, the attack chain becomes:
S3 (SSH key) → EC2 bastion → ECR (container image with secrets)

The deploy script automatically detects if scenario-4 is deployed and attaches
an instance profile to the bastion, giving it ECR read permissions. If scenario-4
is not deployed, the ECR lure works standalone.

## Resource Chain (combined with scenario-4)

```
Attacker (continuing from scenario-4)
  │
  ├─► Already on prod-bastion-host (via SSH key from S3)
  │
  ├─► Queries instance metadata → discovers prod-bastion-ecr-role
  │
  ├─► Calls ecr:GetAuthorizationToken → authenticates to ECR
  │
  ├─► Calls ecr:DescribeRepositories → finds prod-payment-service
  │
  ├─► Calls ecr:ListImages → sees tags: latest, v2.14.3
  │
  └─► Pulls and inspects image
        │
        ├─► /app/.env → DB connection string, Stripe key, Redis URL, JWT secret
        ├─► /app/config/secrets.json → PII records, payment tokens, internal endpoints
        └─► /root/.aws/credentials → ASIA session token (placeholder)
```

## Dependency on Scenario 4

| Scenario-4 Status | Behavior |
|--------------------|----------|
| Deployed | Instance profile auto-attached to bastion → full chain active |
| Not deployed | ECR repo + role deployed standalone, warning printed |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — ECR repo, IAM role, instance profile |
| `deploy.sh` | Deploy script — stack + Docker build/push + optional instance profile attach |
| `fake-data/docker/Dockerfile` | Docker image definition |
| `fake-data/docker/.env` | Fake DB creds, Stripe key, Redis URL |
| `fake-data/docker/config/secrets.json` | Fake PII records, payment tokens, internal endpoints |
| `fake-data/docker/aws-credentials` | ASIA session token placeholder |

## Security Best Practices Applied

- ECR image tag immutability enabled
- Image scanning on push enabled
- ECR encryption enabled (AES256)
- Repository policy scoped to account root principal only
- IAM role trust policy restricted to `ec2.amazonaws.com` service principal
- ECR read permissions scoped to the specific repository ARN
- `GetAuthorizationToken` on `*` (required by ECR, cannot be scoped)
- IAM role session duration capped at 1 hour

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

### What the script does

1. Deploys the CloudFormation stack (ECR repo + IAM role + instance profile)
2. Builds the Docker image from `fake-data/docker/`
3. Authenticates to ECR and pushes with tags `latest` and `v2.14.3`
4. Checks if scenario-4 exists:
   - If yes: attaches instance profile to the bastion
   - If no: prints a warning, ECR lure is standalone

### Deploy order (for full chain)

```bash
# Deploy scenario-4 first (S3 + EC2 bastion)
cd ../scenario-4 && ./deploy.sh

# Then deploy scenario-5 (ECR + auto-attach to bastion)
cd ../scenario-5 && ./deploy.sh
```

## Customization

- Edit `fake-data/docker/config/secrets.json` to add more PII records or endpoints
- Replace PLACEHOLDER values in `fake-data/docker/aws-credentials` with your own
  fake ASIA session tokens before building the image
- Replace `[name]`, `[email]`, `[phone_number]` with realistic fake PII
