# Scenario 3 — Attack Path & Cost Estimation

## Attack Path

```
1. Attacker enumerates IAM roles in the account
2. Discovers: infra-config-readonly-role (assumable by any account principal)
3. Assumes the role via sts:AssumeRole
4. Calls ssm:DescribeParameters → finds /prod/* parameter hierarchy:
   - /prod/database/master-credentials
   - /prod/ci-cd/github-deploy-token
   - /prod/monitoring/datadog-api-keys
   - /prod/vpn/admin-credentials
   - /prod/kubernetes/cluster-admin-kubeconfig
5. Calls ssm:GetParametersByPath /prod/* → bulk retrieves all values
6. Extracts:
   - RDS MySQL master username/password + endpoint
   - GitHub PAT with repo/workflow scope
   - Datadog API + app keys
   - VPN admin console credentials + MFA seed
   - EKS cluster-admin kubeconfig with bearer token
7. Attempts GitHub repo access → triggers detection
8. Attempts VPN login → triggers detection
9. Attempts kubectl commands against EKS endpoint → triggers detection
10. Attempts Datadog API calls → triggers detection
```

## AWS Resources Deployed

| Resource | Type | Pricing Model |
|----------|------|---------------|
| IAM Role + Policy | AWS::IAM::Role, AWS::IAM::Policy | Free |
| SSM Parameter (Standard) x4 | AWS::SSM::Parameter | Free |
| SSM Parameter (Advanced) x1 | AWS::SSM::Parameter | $0.05/month |

## Monthly Cost Estimation

| Component | Estimate |
|-----------|----------|
| SSM Standard parameters (4) | $0.00 |
| SSM Advanced parameter (1 — kubeconfig) | ~$0.05 |
| SSM API calls (minimal, attacker-triggered) | ~$0.00 |
| IAM resources | $0.00 |
| **Total** | **~$0.05/month** |

SSM Parameter Store Standard tier is free. Only the Advanced tier parameter
(kubeconfig, needed for larger payload) costs $0.05/advanced-param/month.
API calls are $0.05 per 10,000 — negligible for a lure.
