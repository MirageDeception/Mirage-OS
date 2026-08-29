# NOTE TO OPEN-SOURCE USERS:
# The resources in this scenario have been deployed with realistic, hardcoded names by default.
# You can safely rename any resource manually in this file to fit your environment's naming conventions.

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "saml_metadata_document" {
  description = "SAML metadata XML document from the IdP (Okta)"
  type        = string
  default     = "<?xml version=\"1.0\"?><EntityDescriptor xmlns=\"urn:oasis:names:tc:SAML:2.0:metadata\"></EntityDescriptor>"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "sso_audit_readonly_role" {
  name                 = "sso-audit-readonly-role"
  description          = "Read-only SSO audit access for identity and access management reviews"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::$${var.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "production"
    Project     = "identity-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-1100"
  }
}

resource "aws_iam_policy" "sso_audit_readonly_policy" {
  name        = "sso-audit-readonly-policy"
  description = "Policy for sso-audit-readonly-role"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SAMLProviderList"
        Effect   = "Allow"
        Action   = ["iam:ListSAMLProviders"]
        Resource = "*"
      },
      {
        Sid      = "SAMLProviderRead"
        Effect   = "Allow"
        Action   = ["iam:GetSAMLProvider"]
        Resource = aws_iam_saml_provider.okta_saml_provider.arn
      },
      {
        Sid      = "RoleList"
        Effect   = "Allow"
        Action   = ["iam:ListRoles"]
        Resource = "*"
      },
      {
        Sid      = "RoleRead"
        Effect   = "Allow"
        Action   = ["iam:GetRole"]
        Resource = [
          aws_iam_role.okta_admin_role.arn,
          aws_iam_role.okta_developer_role.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sso_audit_readonly_attach" {
  role       = aws_iam_role.sso_audit_readonly_role.name
  policy_arn = aws_iam_policy.sso_audit_readonly_policy.arn
}

resource "aws_iam_saml_provider" "okta_saml_provider" {
  name                   = "ProdOktaSSO"
  saml_metadata_document = var.saml_metadata_document

  tags = {
    Environment = "production"
    Project     = "identity-platform"
    SSOProvider = "Okta"
    ManagedBy   = "terraform"
    CostCenter  = "CC-1100"
  }
}

resource "aws_iam_role" "okta_admin_role" {
  name                 = "prod-okta-admin-role"
  description          = "Production administrator access via Okta SSO federation"
  max_session_duration = 14400

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_saml_provider.okta_saml_provider.arn
        }
        Action = "sts:AssumeRoleWithSAML"
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]

  tags = {
    Environment = "production"
    Project     = "identity-platform"
    SSOProvider = "Okta"
    AccessLevel = "admin"
    ManagedBy   = "terraform"
    CostCenter  = "CC-1100"
  }
}

resource "aws_iam_role" "okta_developer_role" {
  name                 = "prod-okta-developer-role"
  description          = "Production developer access via Okta SSO federation"
  max_session_duration = 14400

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_saml_provider.okta_saml_provider.arn
        }
        Action = "sts:AssumeRoleWithSAML"
        Condition = {
          StringEquals = {
            "SAML:aud" = "https://signin.aws.amazon.com/saml"
          }
        }
      }
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]

  tags = {
    Environment = "production"
    Project     = "identity-platform"
    SSOProvider = "Okta"
    AccessLevel = "developer"
    ManagedBy   = "terraform"
    CostCenter  = "CC-1100"
  }
}
