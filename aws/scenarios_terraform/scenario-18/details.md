# scenario-18

Description: SSM Parameter Cross-Reference Chain. Five SSM parameters under /prod/db/* that cross-reference each other via a see_also field, creating a breadcrumb chain the attacker follows. Discovery role: infra-params-readonly-role.

**Resources Deployed:**
- `infra-params-readonly-role` (aws_iam_role)
- `infra-params-readonly-policy` (aws_iam_policy)
- `/prod/db/primary` (aws_ssm_parameter)
- `/prod/db/replica` (aws_ssm_parameter)
- `/prod/db/backup-config` (aws_ssm_parameter)
- `/prod/db/encryption-config` (aws_ssm_parameter)
- `/prod/db/monitoring` (aws_ssm_parameter)
