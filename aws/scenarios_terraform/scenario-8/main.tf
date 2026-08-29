# NOTE TO OPEN-SOURCE USERS:
# The resources in this scenario have been deployed with realistic, hardcoded names by default.
# You can safely rename any resource manually in this file to fit your environment's naming conventions.

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

provider "aws" {
}

data "aws_region" "current" {}

resource "aws_iam_role" "microservice_auth_role" {
  name                 = "prod-microservice-auth-role"
  description          = "Authentication service role for microservices platform"
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
    Project     = "microservices"
    ManagedBy   = "terraform"
    Service     = "auth"
  }
}

resource "aws_iam_role_policy" "microservice_auth_policy" {
  name = "prod-microservice-auth-policy"
  role = aws_iam_role.microservice_auth_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeDataRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.microservice_data_role.arn
      },
      {
        Sid      = "ReadOIDCConfig"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/auth/oidc-config"
      }
    ]
  })
}

resource "aws_iam_role" "microservice_data_role" {
  name                 = "prod-microservice-data-role"
  description          = "Data layer service role for microservices platform"
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
    Project     = "microservices"
    ManagedBy   = "terraform"
    Service     = "data-layer"
  }
}

resource "aws_iam_role_policy" "microservice_data_policy" {
  name = "prod-microservice-data-policy"
  role = aws_iam_role.microservice_data_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeAdminRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.microservice_admin_role.arn
      },
      {
        Sid      = "ReadLakeCredentials"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/data/lake-credentials"
      }
    ]
  })
}

resource "aws_iam_role" "microservice_admin_role" {
  name                 = "prod-microservice-admin-role"
  description          = "Admin console service role for microservices platform"
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
    Project     = "microservices"
    ManagedBy   = "terraform"
    Service     = "admin"
  }
}

resource "aws_iam_role_policy" "microservice_admin_policy" {
  name = "prod-microservice-admin-policy"
  role = aws_iam_role.microservice_admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeAuthRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.microservice_auth_role.arn
      },
      {
        Sid      = "ReadConsoleCredentials"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/admin/console-credentials"
      }
    ]
  })
}

resource "aws_ssm_parameter" "oidc_config_param" {
  name        = "/prod/auth/oidc-config"
  description = "OIDC provider configuration for production authentication service"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "microservices"
    ManagedBy   = "terraform"
    Service     = "auth"
  }
}

resource "aws_ssm_parameter" "lake_credentials_param" {
  name        = "/prod/data/lake-credentials"
  description = "Data lake service account credentials for production ETL pipelines"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "microservices"
    ManagedBy   = "terraform"
    Service     = "data-layer"
  }
}

resource "aws_ssm_parameter" "console_credentials_param" {
  name        = "/prod/admin/console-credentials"
  description = "Admin console service account credentials for production management plane"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "microservices"
    ManagedBy   = "terraform"
    Service     = "admin"
  }
}
