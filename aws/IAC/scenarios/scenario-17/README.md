# Scenario 19 — Lambda + DynamoDB Lure: Data Pipeline with PII Table

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`etl-ops-readonly-role` — assumable by any principal in the account. The role
grants read-only access to Lambda function metadata and configuration.

The attacker lists Lambda functions and finds `prod-user-data-enrichment`.
Reading its configuration reveals environment variables containing what appear
to be live production API keys and a DynamoDB table reference:

- Clearbit API key for company/person enrichment
- FullContact API key for contact data enrichment
- DynamoDB table name: `prod-enriched-user-profiles`

Investigating the Lambda execution role (`prod-user-enrichment-exec-role`)
reveals it has DynamoDB read/write access scoped to the lure table. Scanning
the table exposes enriched user PII records including names, emails, companies,
job titles, LinkedIn profiles, enrichment scores, and revenue estimates.

All values look legitimate and usable. The realistic naming, structure, and
data formats are designed to lure the attacker into attempting to use the API
keys or exfiltrate the PII — triggering detection alerts.

## Deception Chain

```
Attacker
  │
  ├─► Discovers IAM Role: etl-ops-readonly-role
  │     (assumable by any principal in the account)
  │
  ├─► lambda:ListFunctions → finds prod-user-data-enrichment
  │
  ├─► lambda:GetFunctionConfiguration → extracts env vars:
  │     ├─► DYNAMODB_TABLE=prod-enriched-user-profiles
  │     ├─► CLEARBIT_API_KEY=sk_prod_a1b2c3d4e5f6...
  │     └─► FULLCONTACT_API_KEY=fc_prod_7g8h9i0j...
  │
  ├─► Investigates Lambda execution role → has DynamoDB read/write
  │
  ├─► dynamodb:Scan on prod-enriched-user-profiles → reads enriched PII
  │     ├─► Names, emails, company, job title
  │     ├─► LinkedIn profiles, enrichment scores
  │     └─► Revenue estimates, tech stack data
  │
  └─► Attempts to use API keys or exfiltrate PII → triggers detection
```

## Resources

| Resource | Type | Name |
|----------|------|------|
| Discovery Role | IAM Role | `etl-ops-readonly-role` |
| Execution Role | IAM Role | `prod-user-enrichment-exec-role` |
| Lambda Function | Lambda | `prod-user-data-enrichment` |
| PII Table | DynamoDB | `prod-enriched-user-profiles` |

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — Lambda + DynamoDB + 2 IAM roles |
| `deploy.sh` | One-command deploy script — creates the stack and seeds DynamoDB |
| `abuse.sh` | Simulates the attacker abuse chain — assumes role, reads Lambda config, scans DynamoDB |
| `fake-data/enriched-users.json` | 12 enriched user PII records for DynamoDB seeding |

## Security Best Practices Applied

- IAM discovery role: trust policy scoped to account root principal (not public)
- IAM execution role: trust policy scoped to `lambda.amazonaws.com` service principal only
- Execution role DynamoDB permissions scoped to specific table ARN (least privilege)
- Lambda function: no public URL, no function URL, no API Gateway trigger
- Lambda CloudWatch Logs permission scoped to specific log group ARN
- DynamoDB table: PAY_PER_REQUEST billing (no cost when idle)

## Cost

$0.00/month — Lambda not invoked, DynamoDB on-demand with no traffic.

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
  --stack-name deception-scenario-19 \
  --parameter-overrides AccountId=${ACCOUNT_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2 \
  --no-fail-on-empty-changeset

# Seed DynamoDB
for i in $(seq 0 11); do
  ITEM=$(jq -c ".[$i]" fake-data/enriched-users.json)
  aws dynamodb put-item \
    --table-name prod-enriched-user-profiles \
    --item "${ITEM}" \
    --region us-west-2
done
```

## Teardown

```bash
aws cloudformation delete-stack --stack-name deception-scenario-19 --region us-west-2
```
