# Scenario 5 — Attack Path & Cost Estimation

## Attack Path

```
1. Attacker is already on prod-bastion-host (from scenario-4)
2. Checks instance metadata → discovers instance profile: prod-bastion-ecr-role
3. Calls ecr:GetAuthorizationToken → gets Docker registry auth
4. Calls ecr:DescribeRepositories → finds prod-payment-service
5. Calls ecr:ListImages → sees tags: latest, v2.14.3
6. Pulls image: docker pull <account-id>.dkr.ecr.us-west-2.amazonaws.com/prod-payment-service:latest
7. Inspects image layers or runs container → finds:
   - /app/.env → DB connection string, Stripe secret key, Redis URL, JWT secret
   - /app/config/secrets.json → PII records (names, emails, card tokens), internal API endpoints
   - /root/.aws/credentials → ASIA session token
8. Attempts Stripe API calls with extracted key → triggers detection
9. Attempts to access internal endpoints → triggers detection
10. Attempts to use ASIA credentials → triggers detection
11. Attempts to use PII data → triggers detection

Standalone path (without scenario-4):
1. Attacker discovers prod-bastion-ecr-role or gains ECR access another way
2. Authenticates to ECR → pulls prod-payment-service image
3. Continues from step 7 above
```

## AWS Resources Deployed

| Resource | Type | Pricing Model |
|----------|------|---------------|
| IAM Role + Instance Profile | AWS::IAM::Role, AWS::IAM::InstanceProfile | Free |
| ECR Repository | AWS::ECR::Repository | Storage per GB |
| ECR image (~50-100 MB) | Stored in ECR | $0.10/GB/month |

## Monthly Cost Estimation

| Component | Estimate |
|-----------|----------|
| ECR storage (python:3.11-slim based image, ~120 MB) | ~$0.01 |
| ECR data transfer (attacker pull, minimal) | ~$0.00 |
| IAM resources | $0.00 |
| Instance profile attach (no additional cost) | $0.00 |
| **Total (standalone)** | **~$0.01/month** |
| **Total (combined with scenario-4)** | **~$0.65/month** (instance stopped) |

ECR charges $0.10/GB/month for storage. A slim Python-based image is ~120 MB,
so storage cost is negligible. Data transfer for image pulls within the same
region is free. The only meaningful cost is the EC2 instance from scenario-4.

## Combined Scenario 4+5 Cost Summary

| Component | Monthly |
|-----------|---------|
| EC2 t3.nano (scenario-4, stopped) | ~$0.00 |
| EBS 8 GB gp3 (scenario-4, persists) | ~$0.64 |
| S3 bucket (scenario-4) | ~$0.00 |
| ECR storage (scenario-5) | ~$0.01 |
| IAM / VPC / networking | $0.00 |
| **Combined total** | **~$0.65/month** (instance stopped) |
