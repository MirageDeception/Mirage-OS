data "aws_region" "current" {}

# ---------------------------------------------------------------
# IAM Role (Discovery) — log-analysis-readonly-role
# ---------------------------------------------------------------
resource "aws_iam_role" "log_analysis_readonly_role" {
  name                 = "log-analysis-readonly-role"
  description          = "Read-only CloudWatch Logs access for application debugging and analysis"
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
    Project     = "payment-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-5100"
  }
}

resource "aws_iam_role_policy_attachment" "log_analysis_readonly_policy_attachment" {
  role       = aws_iam_role.log_analysis_readonly_role.name
  policy_arn = aws_iam_policy.log_analysis_readonly_policy.arn
}

resource "aws_iam_policy" "log_analysis_readonly_policy" {
  name = "log-analysis-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeLogGroups"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadLogGroup"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${var.account_id}:log-group:/prod/payment-service/application:*"
      }
    ]
  })
}

# ---------------------------------------------------------------
# CloudWatch Log Group — /prod/payment-service/application
# ---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "payment_service_log_group" {
  name              = "/prod/payment-service/application"
  retention_in_days = 30

  tags = {
    Environment = "production"
    Project     = "payment-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-5100"
  }
}
