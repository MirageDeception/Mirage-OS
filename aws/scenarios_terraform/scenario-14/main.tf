data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------
# KMS Key — prod-customer-data-encryption
# ---------------------------------------------------------------
resource "aws_kms_key" "customer_data_key" {
  description             = "Customer PII encryption key for production payment and user data"
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyAllDecrypt"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Environment         = "production"
    Project             = "customer-platform"
    DataClassification  = "PII"
    ManagedBy           = "terraform"
    CostCenter          = "CC-3200"
  }
}

resource "aws_kms_alias" "customer_data_key_alias" {
  name          = "alias/${var.kms_alias}"
  target_key_id = aws_kms_key.customer_data_key.key_id
}

# ---------------------------------------------------------------
# IAM Role (Discovery) — kms-audit-readonly-role
# ---------------------------------------------------------------
resource "aws_iam_role" "kms_audit_readonly_role" {
  name                 = var.role_readonly
  description          = "Read-only KMS audit access for security compliance reviews"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "production"
    Project     = "customer-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3200"
  }
}

resource "aws_iam_role_policy_attachment" "kms_audit_readonly_policy_attachment" {
  role       = aws_iam_role.kms_audit_readonly_role.name
  policy_arn = aws_iam_policy.kms_audit_readonly_policy.arn
}

resource "aws_iam_policy" "kms_audit_readonly_policy" {
  name = "kms-audit-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSListGlobal"
        Effect = "Allow"
        Action = [
          "kms:ListAliases",
          "kms:ListKeys"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSDescribeKey"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:ListGrants",
          "kms:ListKeyPolicies",
          "kms:GetKeyPolicy"
        ]
        Resource = aws_kms_key.customer_data_key.arn
      },
      {
        Sid    = "DenyDecryptOperations"
        Effect = "Deny"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo"
        ]
        Resource = "*"
      }
    ]
  })
}
