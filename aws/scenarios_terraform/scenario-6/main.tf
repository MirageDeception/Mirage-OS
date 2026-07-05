provider "aws" {
}

data "aws_region" "current" {}

resource "aws_iam_role" "lambda_ops_readonly_role" {
  name                 = "lambda-ops-readonly-role"
  description          = "Read-only Lambda operations access for platform engineering team"
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
    Project     = "data-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-6140"
  }
}

resource "aws_iam_role_policy" "lambda_ops_readonly_policy" {
  name = "lambda-ops-readonly-policy"
  role = aws_iam_role.lambda_ops_readonly_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaList"
        Effect   = "Allow"
        Action   = ["lambda:ListFunctions"]
        Resource = "*"
      },
      {
        Sid      = "LambdaReadFunction"
        Effect   = "Allow"
        Action   = [
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:ListTags"
        ]
        Resource = aws_lambda_function.data_sync_processor.arn
      }
    ]
  })
}

resource "aws_iam_role" "data_sync_exec_role" {
  name                 = "prod-data-sync-exec-role"
  description          = "Execution role for prod-data-sync-processor Lambda function"
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
    Environment = "production"
    Project     = "data-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-6140"
  }
}

resource "aws_iam_role_policy" "data_sync_exec_base_policy" {
  name = "prod-data-sync-exec-base-policy"
  role = aws_iam_role.data_sync_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${var.account_id}:log-group:/aws/lambda/prod-data-sync-processor:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "data_sync_exec_s3_policy" {
  count = var.include_s3 ? 1 : 0
  name  = "prod-data-sync-exec-s3-policy"
  role  = aws_iam_role.data_sync_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ReadArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::prod-data-sync-artifacts-${var.account_id}/*"
      },
      {
        Sid      = "S3ListArtifacts"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::prod-data-sync-artifacts-${var.account_id}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "data_sync_exec_sm_policy" {
  count = var.include_secrets_manager ? 1 : 0
  name  = "prod-data-sync-exec-sm-policy"
  role  = aws_iam_role.data_sync_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SecretsManagerRead"
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.api_credentials_secret[0].arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "data_sync_exec_ssm_policy" {
  count = var.include_ssm ? 1 : 0
  name  = "prod-data-sync-exec-ssm-policy"
  role  = aws_iam_role.data_sync_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SSMRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/data-sync/config"
      }
    ]
  })
}

data "archive_file" "data_sync_zip" {
  type        = "zip"
  output_path = "$${path.module}/data_sync.zip"
  source {
    content  = <<EOF
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Production data sync processor.
    Pulls data from analytics DB, transforms, and loads to data lake.
    Triggered on schedule via EventBridge (cron 0 2 * * ? *).
    """
    bucket = os.environ.get('S3_ARTIFACT_BUCKET')
    db_host = os.environ.get('DB_HOST')

    logger.info(f"Starting data sync run for {db_host}")
    logger.info(f"Artifact bucket: {bucket}")

    stages = ['extract', 'transform', 'validate', 'load']
    results = {}

    for stage in stages:
        logger.info(f"Executing stage: {stage}")
        results[stage] = {'status': 'completed', 'records': 0}

    return {
        'statusCode': 200,
        'body': json.dumps({
            'pipeline_id': 'ds-prod-001',
            'status': 'completed',
            'stages': results
        })
    }
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "data_sync_processor" {
  function_name = "prod-data-sync-processor"
  description   = "Production data sync processor - ETL pipeline for analytics data lake"
  role          = aws_iam_role.data_sync_exec_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.data_sync_zip.output_path
  source_code_hash = data.archive_file.data_sync_zip.output_base64sha256

  environment {
    variables = {
      DB_HOST           = "prod-analytics-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com"
      DB_PORT           = "5432"
      DB_NAME           = "analytics_production"
      DB_USER           = "analytics_etl_svc"
      DB_PASSWORD       = "An@lyt1cs#ETL!2024pR0d"
      STRIPE_API_KEY    = "sk_live_51QxHr8eF59JrNzkYGctjU3af2rq9ef"
      SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/T0PROD01/B0PROD02/xYzAbCdEfGhIjKlMnOpQrStU"
      ENCRYPTION_KEY    = "aes256:9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d"
      S3_ARTIFACT_BUCKET= "prod-data-sync-artifacts-${var.account_id}"
    }
  }

  tags = {
    Environment = "production"
    Project     = "data-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-6140"
  }
}

resource "aws_s3_bucket" "data_sync_artifacts_bucket" {
  count  = var.include_s3 ? 1 : 0
  bucket = "prod-data-sync-artifacts-${var.account_id}"

  tags = {
    Environment = "production"
    Project     = "data-platform"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "data_sync_artifacts_versioning" {
  count  = var.include_s3 ? 1 : 0
  bucket = aws_s3_bucket.data_sync_artifacts_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_sync_artifacts_encryption" {
  count  = var.include_s3 ? 1 : 0
  bucket = aws_s3_bucket.data_sync_artifacts_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "data_sync_artifacts_pab" {
  count  = var.include_s3 ? 1 : 0
  bucket = aws_s3_bucket.data_sync_artifacts_bucket[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "data_sync_artifacts_bucket_policy" {
  count  = var.include_s3 ? 1 : 0
  bucket = aws_s3_bucket.data_sync_artifacts_bucket[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAccountRead"
        Effect   = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::prod-data-sync-artifacts-${var.account_id}",
          "arn:aws:s3:::prod-data-sync-artifacts-${var.account_id}/*"
        ]
      },
      {
        Sid      = "DenyInsecureTransport"
        Effect   = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          "arn:aws:s3:::prod-data-sync-artifacts-${var.account_id}",
          "arn:aws:s3:::prod-data-sync-artifacts-${var.account_id}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "api_credentials_secret" {
  count       = var.include_secrets_manager ? 1 : 0
  name        = "prod/data-sync/api-credentials"
  description = "Third-party API credentials for production data sync integrations"
  
  tags = {
    Environment      = "production"
    Project          = "data-platform"
    ManagedBy        = "terraform"
    RotationSchedule = "90days"
  }
}

resource "aws_secretsmanager_secret_version" "api_credentials_secret_version" {
  count         = var.include_secrets_manager ? 1 : 0
  secret_id     = aws_secretsmanager_secret.api_credentials_secret[0].id
  secret_string = "{\"placeholder\": \"replaced-by-deploy-script\"}"
}

resource "aws_secretsmanager_secret_policy" "api_credentials_resource_policy" {
  count      = var.include_secrets_manager ? 1 : 0
  secret_arn = aws_secretsmanager_secret.api_credentials_secret[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAccountRead"
        Effect   = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ssm_parameter" "data_sync_config_param" {
  count       = var.include_ssm ? 1 : 0
  name        = "/prod/data-sync/config"
  description = "Production data sync pipeline configuration and service endpoints"
  type        = "String"
  tier        = "Standard"
  value       = "{\"placeholder\": \"replaced-by-deploy-script\"}"

  tags = {
    Environment = "production"
    Project     = "data-platform"
    ManagedBy   = "terraform"
  }
}
