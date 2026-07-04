# Scenario 1 — Attack Path & Cost Estimation

## Attack Path

```
1. Attacker enumerates IAM roles in the account
2. Discovers: infra-s3-data-readonly-role (assumable by any account principal)
3. Assumes the role via sts:AssumeRole
4. Calls s3:ListAllMyBuckets → finds infra-terraform-state-<account-id>
5. Calls s3:ListBucket → sees env/production/terraform.tfstate
6. Calls s3:GetObject → downloads the state file
7. Parses terraform.tfstate → extracts:
   - RDS endpoint + master credentials
   - Stripe API keys
   - IAM access keys (appear active)
   - Redis auth token
   - SSM parameter with full DB connection string
8. Attempts to use extracted credentials → triggers detection
```

## AWS Resources Deployed

| Resource | Type | Pricing Model |
|----------|------|---------------|
| IAM Role + Policy | AWS::IAM::Role, AWS::IAM::Policy | Free |
| S3 Bucket | AWS::S3::Bucket | Storage + requests |
| S3 Bucket Policy | AWS::S3::BucketPolicy | Free |

## Monthly Cost Estimation

| Component | Estimate |
|-----------|----------|
| S3 storage (single tfstate file, ~5 KB) | ~$0.00 |
| S3 requests (minimal, attacker-triggered only) | ~$0.00 |
| IAM resources | $0.00 |
| **Total** | **~$0.00/month** |

This scenario is essentially free. S3 charges are negligible for a single
small file with minimal access. No compute, no data transfer costs.
