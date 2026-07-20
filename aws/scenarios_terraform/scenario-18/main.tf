provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

resource "aws_iam_role" "infra_params_readonly_role" {
  name                 = var.role_name
  description          = "Read-only infrastructure parameter access for SRE team"
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
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3100"
  }
}

resource "aws_iam_policy" "infra_params_readonly_policy" {
  name = "infra-params-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SSMDescribeAll"
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      },
      {
        Sid      = "SSMReadProdDb"
        Effect   = "Allow"
        Action   = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/db/*"
      },
      {
        Sid      = "SSMGetByPath"
        Effect   = "Allow"
        Action   = ["ssm:GetParametersByPath"]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/db",
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/db/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_params_readonly_attach" {
  role       = aws_iam_role.infra_params_readonly_role.name
  policy_arn = aws_iam_policy.infra_params_readonly_policy.arn
}

resource "aws_ssm_parameter" "db_primary_param" {
  name        = var.param_primary
  description = "Production primary database connection configuration"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3100"
  }
}

resource "aws_ssm_parameter" "db_replica_param" {
  name        = var.param_replica
  description = "Production read replica database connection configuration"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3100"
  }
}

resource "aws_ssm_parameter" "db_backup_config_param" {
  name        = var.param_backup
  description = "Production database backup configuration and S3 storage"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3100"
  }
}

resource "aws_ssm_parameter" "db_encryption_config_param" {
  name        = var.param_encryption
  description = "Production database encryption and TLS configuration"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3100"
  }
}

resource "aws_ssm_parameter" "db_monitoring_param" {
  name        = var.param_monitoring
  description = "Production database monitoring and alerting integration"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3100"
  }
}
