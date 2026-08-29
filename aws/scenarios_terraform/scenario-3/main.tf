# NOTE TO OPEN-SOURCE USERS:
# The resources in this scenario have been deployed with realistic, hardcoded names by default.
# You can safely rename any resource manually in this file to fit your environment's naming conventions.

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

data "aws_region" "current" {}

resource "aws_iam_role" "infra_config_readonly_role" {
  name                 = "infra-config-readonly-role"
  description          = "Read-only access to production infrastructure configuration parameters"
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
    Project     = "platform-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3045"
  }
}

resource "aws_iam_policy" "infra_config_policy" {
  name = "infra-config-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeAllParameters"
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadProdParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/database/master-credentials",
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/ci-cd/github-deploy-token",
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/monitoring/datadog-api-keys",
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/vpn/admin-credentials",
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/kubernetes/cluster-admin-kubeconfig"
        ]
      },
      {
        Sid    = "GetByPath"
        Effect = "Allow"
        Action = [
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod",
          "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_config_policy_attach" {
  role       = aws_iam_role.infra_config_readonly_role.name
  policy_arn = aws_iam_policy.infra_config_policy.arn
}

resource "aws_ssm_parameter" "database_master_credentials" {
  name        = "/prod/database/master-credentials"
  description = "RDS MySQL master credentials for the core platform production database"
  type        = "String"
  tier        = "Standard"
  value       = jsonencode({ "placeholder" : "replaced-by-deploy-script" })

  tags = {
    Environment = "production"
    Project     = "platform-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3045"
  }
}

resource "aws_ssm_parameter" "github_deploy_token" {
  name        = "/prod/ci-cd/github-deploy-token"
  description = "GitHub PAT and deploy key for CI/CD pipeline access to platform-monorepo"
  type        = "String"
  tier        = "Standard"
  value       = jsonencode({ "placeholder" : "replaced-by-deploy-script" })

  tags = {
    Environment = "production"
    Project     = "platform-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3045"
  }
}

resource "aws_ssm_parameter" "datadog_api_keys" {
  name        = "/prod/monitoring/datadog-api-keys"
  description = "Datadog API and application keys for production monitoring and APM"
  type        = "String"
  tier        = "Standard"
  value       = jsonencode({ "placeholder" : "replaced-by-deploy-script" })

  tags = {
    Environment = "production"
    Project     = "platform-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3045"
  }
}

resource "aws_ssm_parameter" "vpn_admin_credentials" {
  name        = "/prod/vpn/admin-credentials"
  description = "VPN appliance admin console credentials and endpoint for production network"
  type        = "String"
  tier        = "Standard"
  value       = jsonencode({ "placeholder" : "replaced-by-deploy-script" })

  tags = {
    Environment = "production"
    Project     = "platform-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3045"
  }
}

resource "aws_ssm_parameter" "eks_kubeconfig" {
  name        = "/prod/kubernetes/cluster-admin-kubeconfig"
  description = "Cluster-admin kubeconfig for prod-platform-cluster EKS cluster"
  type        = "String"
  tier        = "Advanced"
  value       = "placeholder-replaced-by-deploy-script"

  tags = {
    Environment = "production"
    Project     = "platform-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3045"
  }
}
