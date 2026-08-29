# scenario-8

Description: Deception Scenario 9 - IAM Role Chain Loop: three IAM roles in a circular assumption chain (A→B→C→A). Each role has read access to a themed SSM parameter containing fake credentials. Every hop generates CloudTrail events.

**Resources Deployed:**
- `prod-microservice-auth-role` (aws_iam_role)
- `prod-microservice-auth-policy` (aws_iam_role_policy)
- `prod-microservice-data-role` (aws_iam_role)
- `prod-microservice-data-policy` (aws_iam_role_policy)
- `prod-microservice-admin-role` (aws_iam_role)
- `prod-microservice-admin-policy` (aws_iam_role_policy)
- `/prod/auth/oidc-config` (aws_ssm_parameter)
- `/prod/data/lake-credentials` (aws_ssm_parameter)
- `/prod/admin/console-credentials` (aws_ssm_parameter)
