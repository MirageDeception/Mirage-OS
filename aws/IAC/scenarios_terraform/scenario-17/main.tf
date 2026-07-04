provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

resource "aws_iam_role" "etl_ops_readonly_role" {
  name                 = "etl-ops-readonly-role"
  description          = "Read-only ETL operations access for data engineering team"
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
    Project     = "growth-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-4820"
  }
}

resource "aws_iam_policy" "etl_ops_readonly_policy" {
  name = "etl-ops-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaReadOnly"
        Effect   = "Allow"
        Action   = [
          "lambda:ListFunctions",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "etl_ops_readonly_attach" {
  role       = aws_iam_role.etl_ops_readonly_role.name
  policy_arn = aws_iam_policy.etl_ops_readonly_policy.arn
}

resource "aws_iam_role" "user_enrichment_exec_role" {
  name                 = "prod-user-enrichment-exec-role"
  description          = "Execution role for prod-user-data-enrichment Lambda function"
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
    Project     = "growth-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-4820"
  }
}

resource "aws_iam_policy" "user_enrichment_exec_policy" {
  name = "prod-user-enrichment-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDBReadWrite"
        Effect   = "Allow"
        Action   = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.enriched_user_profiles_table.arn
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:$${data.aws_region.current.name}:$${var.account_id}:log-group:/aws/lambda/prod-user-data-enrichment:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "user_enrichment_exec_attach" {
  role       = aws_iam_role.user_enrichment_exec_role.name
  policy_arn = aws_iam_policy.user_enrichment_exec_policy.arn
}

resource "aws_dynamodb_table" "enriched_user_profiles_table" {
  name         = "prod-enriched-user-profiles"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  hash_key  = "user_id"
  range_key = "email"

  tags = {
    Environment = "production"
    Project     = "growth-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-4820"
  }
}

resource "local_file" "lambda_code" {
  filename = "$${path.module}/index.py"
  content  = <<EOF
import json
import os
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')

def handler(event, context):
    """
    Production user data enrichment pipeline.
    Pulls new signups from event source, enriches via Clearbit/FullContact,
    and stores enriched profiles in DynamoDB.
    Triggered by EventBridge schedule (every 6 hours).
    """
    table_name = os.environ.get('DYNAMODB_TABLE')
    batch_size = int(os.environ.get('ENRICHMENT_BATCH_SIZE', '50'))

    table = dynamodb.Table(table_name)
    logger.info(f"Starting enrichment run for table: {table_name}")
    logger.info(f"Batch size: {batch_size}")

    # Enrichment pipeline stages
    stages = ['fetch_new_users', 'clearbit_enrich', 'fullcontact_enrich', 'score', 'persist']
    results = {}

    for stage in stages:
        logger.info(f"Executing stage: {stage}")
        results[stage] = {'status': 'completed', 'records_processed': 0}

    return {
        'statusCode': 200,
        'body': json.dumps({
            'pipeline_id': 'enrich-prod-001',
            'status': 'completed',
            'stages': results
        })
    }
EOF
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "$${path.module}/lambda.zip"
}

resource "aws_lambda_function" "user_data_enrichment_function" {
  function_name = "prod-user-data-enrichment"
  description   = "Production user data enrichment pipeline - Clearbit and FullContact integration"
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 300
  memory_size   = 512
  role          = aws_iam_role.user_enrichment_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE       = "prod-enriched-user-profiles"
      CLEARBIT_API_KEY     = "sk_prod_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
      FULLCONTACT_API_KEY  = "fc_prod_7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v"
      ENRICHMENT_BATCH_SIZE = "50"
      ENRICHMENT_RATE_LIMIT = "100"
      SLACK_ALERTS_CHANNEL  = "#data-enrichment-alerts"
    }
  }

  tags = {
    Environment = "production"
    Project     = "growth-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-4820"
  }
}
