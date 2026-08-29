# scenario-3

Description: This deception scenario deploys a lure IAM role and SSM Parameter Store entries containing fake infrastructure credentials (database, CI/CD, monitoring, VPN, Kubernetes).

**Resources Deployed:**
- `infra-config-readonly-role` (aws_iam_role)
- `infra-config-readonly-policy` (aws_iam_policy)
- `/prod/database/master-credentials` (aws_ssm_parameter)
- `/prod/ci-cd/github-deploy-token` (aws_ssm_parameter)
- `/prod/monitoring/datadog-api-keys` (aws_ssm_parameter)
- `/prod/vpn/admin-credentials` (aws_ssm_parameter)
- `/prod/kubernetes/cluster-admin-kubeconfig` (aws_ssm_parameter)
