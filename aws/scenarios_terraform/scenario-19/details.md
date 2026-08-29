# scenario-19

Description: CloudFormation Stack Outputs Lure: Exposed Infrastructure Secrets. A minimal stack that creates SSM parameters as placeholders but exposes realistic-looking credentials in its stack outputs and cross-stack exports. Discovery role: cfn-audit-readonly-role.

**Resources Deployed:**
- `cfn-audit-readonly-role` (aws_iam_role)
- `cfn-audit-readonly-policy` (aws_iam_policy)
- `/prod/core-infra/endpoints` (aws_ssm_parameter)
- `/prod/core-infra/secrets-ref` (aws_ssm_parameter)
