provider "aws" {
}

resource "aws_iam_role" "customer_data_readonly_role" {
  name                 = var.role_readonly
  description          = "Read-only access to customer data stores for analytics and monitoring"
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
    Project     = "customer-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-4210"
  }
}

resource "aws_iam_role_policy" "customer_data_list_policy" {
  name = "customer-data-list-policy"
  role = aws_iam_role.customer_data_readonly_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDBListTables"
        Effect   = "Allow"
        Action   = ["dynamodb:ListTables"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "customer_profiles_read_policy" {
  count = var.include_customer_profiles ? 1 : 0
  name  = "customer-profiles-readonly-policy"
  role  = aws_iam_role.customer_data_readonly_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCustomerProfiles"
        Effect   = "Allow"
        Action   = [
          "dynamodb:DescribeTable",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.customer_profiles_table[0].arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "active_sessions_read_policy" {
  count = var.include_active_sessions ? 1 : 0
  name  = "active-sessions-readonly-policy"
  role  = aws_iam_role.customer_data_readonly_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadActiveSessions"
        Effect   = "Allow"
        Action   = [
          "dynamodb:DescribeTable",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.active_sessions_table[0].arn
      }
    ]
  })
}

resource "aws_dynamodb_table" "customer_profiles_table" {
  count        = var.include_customer_profiles ? 1 : 0
  name         = var.table_profiles
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "customer_id"
  range_key = "email"

  attribute {
    name = "customer_id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = "production"
    Project     = "customer-platform"
    ManagedBy   = "terraform"
  }
}

resource "aws_dynamodb_table" "active_sessions_table" {
  count        = var.include_active_sessions ? 1 : 0
  name         = var.table_sessions
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "session_id"
  range_key = "user_id"

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
