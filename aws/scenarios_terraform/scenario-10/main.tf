# ---------------------------------------------------------------
# IAM Role — session-store-readonly-role
# ---------------------------------------------------------------
resource "aws_iam_role" "session_store_readonly_role" {
  name                 = "session-store-readonly-role"
  description          = "Read-only access to session store for platform monitoring"
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
    Project     = "auth-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-3180"
  }
}

resource "aws_iam_role_policy_attachment" "session_store_readonly_policy_attachment" {
  role       = aws_iam_role.session_store_readonly_role.name
  policy_arn = aws_iam_policy.session_store_readonly_policy.arn
}

resource "aws_iam_policy" "session_store_readonly_policy" {
  name = "session-store-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBListTables"
        Effect = "Allow"
        Action = [
          "dynamodb:ListTables"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBReadTable"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.active_sessions_table.arn
      }
    ]
  })
}

# ---------------------------------------------------------------
# DynamoDB Table — prod-active-sessions
# ---------------------------------------------------------------
resource "aws_dynamodb_table" "active_sessions_table" {
  name         = "prod-active-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  range_key    = "user_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = "production"
    Project     = "auth-platform"
    ManagedBy   = "terraform"
  }
}
