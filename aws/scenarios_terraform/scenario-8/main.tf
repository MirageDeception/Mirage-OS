provider "aws" {
}

data "aws_region" "current" {}

resource "aws_iam_role" "microservice_auth_role" {
  name                 = var.role_auth
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
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter${var.param_auth}"
      }
    ]
  })
}

resource "aws_iam_role" "microservice_data_role" {
  name                 = var.role_data
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
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter${var.param_data}"
      }
    ]
  })
}

resource "aws_iam_role" "microservice_admin_role" {
  name                 = var.role_admin
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
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter${var.param_admin}"
      }
    ]
  })
}

resource "aws_ssm_parameter" "oidc_config_param" {
  name        = var.param_auth
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
  name        = var.param_data
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
  name        = var.param_admin
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
