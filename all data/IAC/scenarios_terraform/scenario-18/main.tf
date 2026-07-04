provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

resource "aws_iam_role" "resource_inventory_readonly_role" {
  name                 = "resource-inventory-readonly-role"
  description          = "Read-only resource inventory access for cloud governance team"
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
    Project     = "cloud-governance"
    ManagedBy   = "terraform"
    CostCenter  = "CC-7200"
  }
}

resource "aws_iam_policy" "resource_inventory_readonly_policy" {
  name = "resource-inventory-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TaggingAPIs"
        Effect   = "Allow"
        Action   = [
          "tag:GetResources",
          "tag:GetTagKeys",
          "tag:GetTagValues",
          "resourcegroupstaggingapi:GetResources"
        ]
        Resource = "*"
      },
      {
        Sid      = "ServiceSpecificTagReads"
        Effect   = "Allow"
        Action   = [
          "iam:ListRoleTags",
          "lambda:ListTags",
          "s3:GetBucketTagging",
          "ssm:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "resource_inventory_readonly_attach" {
  role       = aws_iam_role.resource_inventory_readonly_role.name
  policy_arn = aws_iam_policy.resource_inventory_readonly_policy.arn
}

resource "aws_iam_role" "backup_automation_role" {
  name                 = "prod-backup-automation-role"
  description          = "Automated backup orchestration for production workloads"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment       = "production"
    Project           = "backup-orchestration"
    ManagedBy         = "terraform"
    CostCenter        = "CC-7200"
    ConfigBackup      = "s3://prod-config-backup-vault/iam-export.json"
    SecretsRef        = "arn:aws:secretsmanager:us-west-2:$${var.account_id}:secret:prod/master-api-keys"
    EncryptionKeyRef  = "alias/prod-master-encryption"
    RelatedPipeline   = "arn:aws:codepipeline:us-west-2:$${var.account_id}:prod-backup-pipeline"
  }
}

resource "aws_ssm_parameter" "service_registry_param" {
  name        = "/prod/inventory/service-registry"
  description = "Production service registry — microservice endpoints and health check configuration"
  type        = "String"
  tier        = "Standard"
  value       = <<EOF
{
  "registry_version": "3.2.1",
  "last_updated": "2026-04-18T03:22:00Z",
  "services": {
    "user-api": {
      "endpoint": "https://user-api.prod.internal.corp:8443/v2",
      "health_check": "/healthz",
      "owner": "platform-team"
    },
    "payment-gateway": {
      "endpoint": "https://payments.prod.internal.corp:8443/v1",
      "health_check": "/status",
      "owner": "fintech-team"
    },
    "notification-service": {
      "endpoint": "https://notify.prod.internal.corp:8443/v1",
      "health_check": "/ping",
      "owner": "engagement-team"
    }
  },
  "config_bucket": "s3://prod-service-configs-$${var.account_id}/registry/"
}
EOF

  tags = {
    Environment         = "production"
    Project             = "cloud-governance"
    ManagedBy           = "terraform"
    CostCenter          = "CC-7200"
    RelatedRole         = "arn:aws:iam::$${var.account_id}:role/prod-data-admin-role"
    BackupBucket        = "s3://prod-dynamodb-backups/customer-data/"
    MonitoringDashboard = "arn:aws:cloudwatch::$${var.account_id}:dashboard/prod-service-health"
  }
}
