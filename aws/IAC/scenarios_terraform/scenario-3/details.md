# Scenario 3 Details

This deception scenario deploys a lure IAM role and SSM Parameter Store entries containing fake infrastructure credentials (database, CI/CD, monitoring, VPN, Kubernetes).

## Resources Created
- **IAM Role** (`infra-config-readonly-role`): Appears as an infra config reader role.
- **SSM Parameters**:
  - `/prod/database/master-credentials`
  - `/prod/ci-cd/github-deploy-token`
  - `/prod/monitoring/datadog-api-keys`
  - `/prod/vpn/admin-credentials`
  - `/prod/kubernetes/cluster-admin-kubeconfig`
