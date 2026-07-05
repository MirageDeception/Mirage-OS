# Deception Scenario 16 - KMS Key Lure

**Description:**
KMS key lure with a fake customer data encryption key. The lure role can describe and list the keys, but decryption is explicitly denied.

**Resources Created:**
1. `prod-customer-data-encryption` (KMS Key & Alias) - Customer-managed symmetric key. Key policy explicitly denies decryption operations.
2. `kms-audit-readonly-role` (IAM Role) - Grants describe/list access to KMS keys for audit purposes.
3. `kms-audit-readonly-policy` (IAM Policy) - Allows KMS list and describe actions, but strictly denies decryption operations.
