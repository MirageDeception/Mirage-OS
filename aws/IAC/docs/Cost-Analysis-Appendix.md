# Cloud Deception — Cost Analysis Appendix

**Project:** AWS Cloud Deception Infrastructure | **Date:** June 2026 | **Classification:** Internal

---

## A. Per-Service Cost Analysis

| Service | Standing Cost (to keep decoy deployed) | Cost Per API Call |
|---------|---------------------------------------|-------------------|
| S3 Bucket | $0.023/GB-month storage (decoy files are tiny → ~$0) | GET: $0.0004/1K requests · PUT: $0.005/1K requests |
| Secrets Manager | $0.40 per secret/month | $0.05 per 10K API calls |
| SSM Parameter Store (Standard) | Free | Free (Advanced: $0.05 per 10K API calls) |
| IAM | Free | Free |
| STS | Free | Free |
| ECR | $0.10/GB-month | Free (API calls free; data transfer on pull only) |
| Lambda | Free (when not invoked) | $0.20 per 1M invocations + compute |
| DynamoDB (On-Demand) | $0.25/GB-month storage | Read: $0.25 per 1M RRU · Write: $1.25 per 1M WRU |
| KMS | $1.00 per key/month | $0.03 per 10K API calls |
| CloudFormation | Free | Free |
| EC2 (Scenario 4) | $0.00 (deployed stopped; EBS 8GB gp3 only: $0.64/mo) | Describe calls: Free |
| SQS | Free (no traffic) | Free |
| SNS | Free (no messages) | Free |
| CloudWatch Logs | Free (minimal storage) | Free |

---

## B. Decoy Resources (Fixed Monthly Cost Per Account)

| # | Scenario | Paid Service | Unit Cost | Monthly Cost |
|---|----------|-------------|-----------|-------------|
| 1 | Terraform State Lure | — | — | $0.00 |
| 2 | Payment Credentials | Secrets Manager (×3) | $0.40/secret | $1.20 |
| 3 | Infrastructure Vault | SSM Advanced (×1) | $0.05/param | $0.05 |
| 4 | SSH Key → EC2 Bastion | EBS 8GB gp3 (stopped) | $0.08/GB | $0.64 |
| 5 | ECR Container Image | ECR storage (~50MB) | $0.10/GB | $0.01 |
| 6 | Lambda Data Sync | Secrets Manager (×1) | $0.40/secret | $0.40 |
| 7 | Lambda Role Chaining | Secrets Manager (×1) | $0.40/secret | $0.40 |
| 8 | Role Chain Loop | — | — | $0.00 |
| 9 | Customer Profiles | — | — | $0.00 |
| 10 | Active Sessions | — | — | $0.00 |
| 11 | Payment Events DLQ | — | — | $0.00 |
| 12 | Critical Alerts (SNS) | — | — | $0.00 |
| 13 | Leaked Logs | — | — | $0.00 |
| 14 | Encryption Key | KMS CMK | $1.00/key | $1.00 |
| 15 | Fake SSO (SAML) | — | — | $0.00 |
| 16 | Tag Breadcrumbs | — | — | $0.00 |
| 17 | Enriched User PII | — | — | $0.00 |
| 18 | SSM Chain | — | — | $0.00 |
| 19 | Stack Outputs | — | — | $0.00 |
| | **Total (all 19 scenarios)** | | | **~$3.70** |

**Free scenarios (12):** 1, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 19
**Paid scenarios (7):** 2, 3, 4, 5, 6, 7, 14

---

## C. Monitoring Stack Cost

| Component | Description | Cost Per Service | Cost Per Alert |
|-----------|-------------|-----------------|----------------|
| EventBridge Default Bus | Listens to all CloudTrail events in account — source for event matching | $0.00 | $0.00 |
| EventBridge Rule A (Forwarding) | Matches decoy activity and forwards cross-account. Rule itself is free; billing based on events published. | $1.00 per million events | $0.000001 |
| EventBridge Global Bus | Centralized bus in security account for decoy events only | $0.00 | $0.00 |
| EventBridge Rule B (Detection) | Routes events by service/scenario. No events published at this layer — charges on matching only. | $0.00 | $0.00 |
| Lambda invocation | Alert enrichment and log classification | $0.20 per million | $0.0000002 |
| Lambda compute | ~250ms × 128MB per invocation | $0.0000166667/GB-sec | $0.0000005 |
| SNS publish (API request) | Publish to alert topic | $0.50 per million | $0.0000005 |
| SNS HTTPS delivery (Torq) | Webhook delivery to SOAR platform (Torq) | $0.60 per million | $0.0000006 |
| **Total per alert** | | | **~$0.000003** |

*Above calculation refers to cost of 1 alert traversing the full pipeline. Cost may vary based on AWS pricing changes.*

---

## D. Organization-Wide Projections (100 Accounts)

| Deployment Model | Scenarios/Account | Per Account | 100 Accounts/Month |
|-----------------|-------------------|-------------|-------------------|
| Free-tier only | 12 (all $0 scenarios) | $0.00 | **$0/month** |
| Core paid (1, 2, 3, 8) | 4 | ~$1.25 | ~$125/month |
| Tiered (4 core + 2–4 random) | 6–8 | ~$1.50–$2.00 | **~$150–$200/month** |
| Full (all 19) | 19 | ~$3.70 | ~$370/month |

---

## E. Summary

| Category | Type | Estimate |
|----------|------|----------|
| Decoy resources (tiered deployment) | Fixed monthly | ~$150–$200/month |
| Monitoring stack | Per-alert (usage-based) | ~$0/month |
| **Total (org-wide)** | | **~$150–$200/month** |

---

## Note

*These are estimates based on current AWS pricing (June 2026) and a tiered deployment model of 6–8 scenarios per account. Actual costs may vary depending on scenario selection and AWS pricing changes. To minimize cost, 12 of 19 scenarios use only free-tier services and can be deployed at $0/account — paid scenarios should be added selectively based on each account's risk profile. Monitoring costs are usage-based (~$0.000003/alert) and effectively negligible at expected alert volumes.*
