provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

resource "aws_iam_role" "cfn_audit_readonly_role" {
  name                 = "cfn-audit-readonly-role"
  description          = "Read-only CloudFormation audit access for compliance team"
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
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-1050"
  }
}

resource "aws_iam_policy" "cfn_audit_readonly_policy" {
  name = "cfn-audit-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudFormationReadOnly"
        Effect   = "Allow"
        Action   = [
          "cloudformation:ListStacks",
          "cloudformation:DescribeStacks",
          "cloudformation:ListExports",
          "cloudformation:GetTemplate"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cfn_audit_readonly_attach" {
  role       = aws_iam_role.cfn_audit_readonly_role.name
  policy_arn = aws_iam_policy.cfn_audit_readonly_policy.arn
}

resource "aws_ssm_parameter" "infra_endpoint_param" {
  name        = "/prod/core-infra/endpoints"
  description = "Production core infrastructure service endpoints"
  type        = "String"
  tier        = "Standard"
  value       = <<EOF
{
  "database": "prod-core-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com:5432",
  "cache": "prod-cache.r3k8m2.0001.usw2.cache.amazonaws.com:6379",
  "api_gateway": "https://k7x9m2p4q1.execute-api.us-west-2.amazonaws.com/prod",
  "admin_dashboard": "https://admin.prod.internal.corp",
  "vpc_id": "vpc-0a1b2c3d4e5f67890",
  "private_subnets": ["subnet-0a1b2c3d4e5f6789a", "subnet-0b2c3d4e5f6789a1b"],
  "db_security_group": "sg-0a1b2c3d4e5f67890"
}
EOF

  tags = {
    Environment = "production"
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-1050"
  }
}

resource "aws_ssm_parameter" "infra_secrets_param" {
  name        = "/prod/core-infra/secrets-ref"
  description = "Production core infrastructure secrets reference map"
  type        = "String"
  tier        = "Standard"
  value       = <<EOF
{
  "database_password_ref": "arn:aws:secretsmanager:us-west-2:$${var.account_id}:secret:prod/core-db/master",
  "api_key_ref": "arn:aws:secretsmanager:us-west-2:$${var.account_id}:secret:prod/api-gateway/key",
  "redis_auth_ref": "arn:aws:secretsmanager:us-west-2:$${var.account_id}:secret:prod/redis/auth-token",
  "last_audit": "2026-04-20T14:30:00Z"
}
EOF

  tags = {
    Environment = "production"
    Project     = "core-infrastructure"
    ManagedBy   = "terraform"
    CostCenter  = "CC-1050"
  }
}
