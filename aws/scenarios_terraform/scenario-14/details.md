# scenario-14

Description: KMS key lure with a fake customer data encryption key. The lure role can describe and list the keys, but decryption is explicitly denied.

**Resources Deployed:**
- `alias/prod-customer-data-encryption` (aws_kms_alias)
- `kms-audit-readonly-role` (aws_iam_role)
- `kms-audit-readonly-policy` (aws_iam_policy)
