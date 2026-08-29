# scenario-16

Description: Resource Tags Breadcrumb Trail. Minimal resources (IAM roles + SSM parameter) tagged with ARNs and S3 URIs that reference other resources. An attacker who enumerates tags discovers a trail of breadcrumbs leading to additional (possibly non-existent) targets, generating CloudTrail events at every hop. Discovery role: resource-inventory-readonly-role. This scenario involves: 1. `resource-inventory-readonly-role`: A discovery role allowing attackers to query resource tags. 2. `prod-backup-automation-role`: An IAM role tagged with multiple deceptive secrets and pipeline ARNs. 3. `/prod/inventory/service-registry`: An SSM parameter seeded with deceptive service registry data and tagged with further deceptive resource ARNs.

**Resources Deployed:**
- `resource-inventory-readonly-role` (aws_iam_role)
- `resource-inventory-readonly-policy` (aws_iam_policy)
- `prod-backup-automation-role` (aws_iam_role)
- `/prod/inventory/service-registry` (aws_ssm_parameter)
