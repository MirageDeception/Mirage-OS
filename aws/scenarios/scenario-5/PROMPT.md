# Scenario 5 — ECR Lure: Container Image with Fake PII, Credentials & ASIA Token

## Prompt

Create a deception scenario called `scenario-5` using CloudFormation template.

**Important**: Do NOT use `FAKE`, `EXPIRED`, `REVOKED`, or `REDACTED` in any key names,
values, labels, or content. All credentials and data must look legitimate and usable to
maximize attacker engagement.

**Dependency**: This scenario extends scenario-4. The deploy script must check if
scenario-4's CloudFormation stack (`deception-scenario-4`) exists. If it does, this
scenario attaches an instance profile (with ECR read permissions) to the scenario-4
EC2 bastion instance — creating the full attack chain. If scenario-4 is not deployed,
this scenario still deploys the ECR repo and role standalone.

### Deception Chain Overview (when combined with scenario-4)

```
Attacker (continuing from scenario-4)
  │
  ├─► Already on prod-bastion-host (via SSH key from S3)
  │
  ├─► Discovers instance profile: prod-bastion-ecr-role
  │     └─► Has ECR read permissions
  │
  ├─► Authenticates to ECR ─► lists repositories
  │
  ├─► Finds ECR Repository: prod-payment-service
  │
  ├─► Pulls container image ─► inspects layers
  │     │
  │     ├─► /app/.env — DB creds, Stripe keys, Redis URL
  │     ├─► /app/config/secrets.json — PII records, payment tokens, internal endpoints
  │     └─► /root/.aws/credentials — ASIA session token (placeholder to fill later)
  │
  └─► Attacker attempts to use credentials ─► triggers alerts
```

### Lure Resources

- **IAM Role (Instance Profile)**: Named `prod-bastion-ecr-role`
  - `ecr:GetAuthorizationToken` — on `*` (required by ECR)
  - `ecr:BatchGetImage` — scoped to the lure ECR repo only
  - `ecr:GetDownloadUrlForLayer` — scoped to the lure ECR repo only
  - `ecr:DescribeRepositories` — scoped to the lure ECR repo only
  - `ecr:ListImages` — scoped to the lure ECR repo only
  - Trust policy: `ec2.amazonaws.com` service principal (for instance profile)

- **ECR Repository**: Named `prod-payment-service`
  - Repository policy allows pull from account root principal
  - Image tag immutability enabled
  - Image scanning on push enabled
  - Contains a Docker image with fake secrets baked into the filesystem

### Fake Data to Seed (baked into Docker image)

- `fake-data/docker/Dockerfile`:
  ```dockerfile
  FROM python:3.11-slim
  WORKDIR /app
  COPY .env /app/.env
  COPY config/secrets.json /app/config/secrets.json
  COPY aws-credentials /root/.aws/credentials
  CMD ["python", "-m", "http.server", "8080"]
  ```

- `fake-data/docker/.env`:
  ```
  DATABASE_URL=postgresql://payments_admin:Kj8#mR2xVn5qW9tL@prod-payments-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com:5432/payments_prod
  STRIPE_SECRET_KEY=sk_live_51NxGr7eD48IqMzkXEbsjT2ze1qp8dc
  REDIS_URL=redis://:r3d1s_pr0d_t0k3n_8xK2mV@prod-payments-cache.eabc12.0001.usw2.cache.amazonaws.com:6379/0
  JWT_SECRET=jwtS1gn1ng_s3cr3t_pr0d_7fA9bC1dE3
  AWS_DEFAULT_REGION=us-west-2
  ```

- `fake-data/docker/config/secrets.json`:
  ```json
  {
    "payment_processor": {
      "stripe_sk": "sk_live_51NxGr7eD48IqMzkXEbsjT2ze1qp8dc",
      "merchant_account": "acct_1NxProd7eMerchant"
    },
    "customer_data_encryption_key": "aes256:b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9",
    "pii_records": [
      {
        "customer_id": "cust_9x8w7v6u5t4s",
        "name": "[name]",
        "email": "[email]",
        "phone": "[phone_number]",
        "card_last4": "4242",
        "card_token": "tok_1NxPr0dC4rdT0k3n"
      },
      {
        "customer_id": "cust_3r2q1p0o9n8m",
        "name": "[name]",
        "email": "[email]",
        "phone": "[phone_number]",
        "card_last4": "1234",
        "card_token": "tok_2MxPr0dC4rdT0k3n"
      },
      {
        "customer_id": "cust_7k6j5i4h3g2f",
        "name": "[name]",
        "email": "[email]",
        "phone": "[phone_number]",
        "card_last4": "5678",
        "card_token": "tok_3LxPr0dC4rdT0k3n"
      }
    ],
    "internal_endpoints": {
      "order_api": "https://api.prod.internal.corp/v2/orders",
      "inventory_api": "https://api.prod.internal.corp/v2/inventory",
      "notification_api": "https://api.prod.internal.corp/v2/notifications",
      "admin_dashboard": "https://admin.prod.internal.corp"
    }
  }
  ```

- `fake-data/docker/aws-credentials`:
  ```ini
  [default]
  aws_access_key_id = ASIAPLACHOLDER000001
  aws_secret_access_key = PLACEHOLDER_SECRET_KEY_FILL_LATER
  aws_session_token = PLACEHOLDER_SESSION_TOKEN_FILL_LATER
  region = us-west-2
  ```

### Resource Naming Style

- ECR repo: `prod-payment-service`
- Instance profile role: `prod-bastion-ecr-role`
- Tags on all resources: `Environment=production`, `Project=payment-platform`, `ManagedBy=terraform`, `CostCenter=CC-5830`

### Deploy Script Logic

The `deploy.sh` must:

1. Deploy the scenario-5 CloudFormation stack (ECR repo + IAM role + instance profile)
2. Build the Docker image from `fake-data/docker/`
3. Authenticate to ECR and push the image as `prod-payment-service:latest` and `prod-payment-service:v2.14.3`
4. Check if scenario-4 stack (`deception-scenario-4`) exists:
   - If YES: attach the instance profile to the scenario-4 EC2 instance using `aws ec2 associate-iam-instance-profile`
   - If NO: print a warning that scenario-4 is not deployed, the ECR lure is standalone

### Additional Requirements

- [ ] All resources must follow security best practices (image scanning, tag immutability, least privilege IAM)
- [ ] ECR repository policy allows pull from account root principal only
- [ ] Instance profile role trust policy is `ec2.amazonaws.com` only
- [ ] IAM permissions scoped to the specific ECR repo ARN (except `GetAuthorizationToken` which requires `*`)
- [ ] Docker image must be built and pushed during deployment
- [ ] ASIA token fields in aws-credentials use `PLACEHOLDER` — to be filled in manually later
- [ ] PII fields use generic `[name]`, `[email]`, `[phone_number]` placeholders per project convention
- [ ] Include a `README.md` explaining the deception chain, dependency on scenario-4, and deployment steps
- [ ] Default region: `us-west-2`
- [ ] Place everything under `scenarios/scenario-5/`

### Output Structure

```
scenarios/scenario-5/
├── template.yaml              # CloudFormation — ECR repo, IAM role, instance profile
├── deploy.sh                  # Deploy stack + docker build/push + optional instance profile attach
├── fake-data/
│   └── docker/
│       ├── Dockerfile
│       ├── .env
│       ├── config/
│       │   └── secrets.json
│       └── aws-credentials
└── README.md
```
