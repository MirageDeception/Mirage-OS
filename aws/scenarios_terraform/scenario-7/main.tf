provider "aws" {
}

data "aws_region" "current" {}

resource "aws_iam_role" "standalone_discovery_role" {
  count                = var.link_to_scenario_6 ? 0 : 1
  name                 = var.role_discovery
  description          = "Lambda operations access with code update capability for data engineering"
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

resource "aws_iam_role_policy" "standalone_discovery_policy" {
  count = var.link_to_scenario_6 ? 0 : 1
  name  = "lambda-inject-readonly-policy"
  role  = aws_iam_role.standalone_discovery_role[0].id

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
        Sid      = "LambdaFullAccess"
        Effect   = "Allow"
        Action   = [
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:ListTags",
          "lambda:InvokeFunction",
          "lambda:UpdateFunctionCode"
        ]
        Resource = aws_lambda_function.standalone_lambda[0].arn
      }
    ]
  })
}

resource "aws_iam_role" "standalone_exec_role" {
  count                = var.link_to_scenario_6 ? 0 : 1
  name                 = var.role_exec
  description          = "Execution role for Lambda code injection scenario"
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
  }
}

resource "aws_iam_role_policy" "standalone_exec_policy" {
  count = var.link_to_scenario_6 ? 0 : 1
  name  = "prod-data-inject-exec-policy"
  role  = aws_iam_role.standalone_exec_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Read"
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::prod-data-inject-artifacts-${var.account_id}",
          "arn:aws:s3:::prod-data-inject-artifacts-${var.account_id}/*"
        ]
      },
      {
        Sid      = "SSMRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${var.account_id}:parameter/prod/data-inject/config"
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${var.account_id}:log-group:/aws/lambda/${var.lambda_name}:*"
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  count       = var.link_to_scenario_6 ? 0 : 1
  type        = "zip"
  output_path = "$${path.module}/lambda.zip"
  source {
    content  = <<EOF
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    bucket = os.environ.get('S3_ARTIFACT_BUCKET', 'none')
    db_host = os.environ.get('DB_HOST')
    logger.info(f"Starting data sync run for {db_host}")
    stages = ['extract', 'transform', 'validate', 'load']
    results = {s: {'status': 'completed', 'records': 0} for s in stages}
    return {'statusCode': 200, 'body': json.dumps({'status': 'completed', 'stages': results})}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "standalone_lambda" {
  count         = var.link_to_scenario_6 ? 0 : 1
  function_name = var.lambda_name
  description   = "Production data injection processor - ETL pipeline"
  role          = aws_iam_role.standalone_exec_role[0].arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  environment {
    variables = {
      DB_HOST       = "prod-analytics-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com"
      DB_PORT       = "5432"
      DB_NAME       = "analytics_production"
      DB_USER       = "analytics_etl_svc"
      DB_PASSWORD   = "An@lyt1cs#ETL!2024pR0d"
      STRIPE_API_KEY = "sk_live_51QxHr8eF59JrNzkYGctjU3af2rq9ef"
      ENCRYPTION_KEY = "aes256:9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d"
    }
  }

  tags = {
    Environment = "production"
    Project     = "data-platform"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "linked_inject_policy" {
  count = var.link_to_scenario_6 ? 1 : 0
  name  = "lambda-code-inject-policy"
  role  = var.scenario_6_discovery_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaInjectPermissions"
        Effect   = "Allow"
        Action   = [
          "lambda:InvokeFunction",
          "lambda:UpdateFunctionCode"
        ]
        Resource = var.scenario_6_function_arn
      }
    ]
  })
}
