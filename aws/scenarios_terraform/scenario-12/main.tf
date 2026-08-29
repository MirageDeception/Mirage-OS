# NOTE TO OPEN-SOURCE USERS:
# The resources in this scenario have been deployed with realistic, hardcoded names by default.
# You can safely rename any resource manually in this file to fit your environment's naming conventions.

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

data "aws_region" "current" {}

# ---------------------------------------------------------------
# IAM Role (Discovery) — alerts-readonly-role
# ---------------------------------------------------------------
resource "aws_iam_role" "alerts_readonly_role" {
  name                 = "alerts-readonly-role"
  description          = "Read-only access to SNS alerting infrastructure for SRE team"
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
    Project     = "sre-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-4200"
  }
}

resource "aws_iam_role_policy_attachment" "alerts_readonly_policy_attachment" {
  role       = aws_iam_role.alerts_readonly_role.name
  policy_arn = aws_iam_policy.alerts_readonly_policy.arn
}

resource "aws_iam_policy" "alerts_readonly_policy" {
  name = "alerts-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SNSListTopics"
        Effect = "Allow"
        Action = [
          "sns:ListTopics"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSReadTopic"
        Effect = "Allow"
        Action = [
          "sns:GetTopicAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:ListTagsForResource"
        ]
        Resource = aws_sns_topic.critical_alerts_topic.arn
      }
    ]
  })
}

# ---------------------------------------------------------------
# SNS Topic — prod-alerts-critical
# ---------------------------------------------------------------
resource "aws_sns_topic" "critical_alerts_topic" {
  name              = "prod-alerts-critical"
  display_name      = "Production Critical Alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Environment = "production"
    Project     = "sre-platform"
    Severity    = "critical"
    ManagedBy   = "terraform"
    CostCenter  = "CC-4200"
  }
}

resource "aws_sns_topic_policy" "critical_alerts_topic_policy" {
  arn = aws_sns_topic.critical_alerts_topic.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountPublish"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.critical_alerts_topic.arn
      },
      {
        Sid       = "DenyExternalPublish"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.critical_alerts_topic.arn
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = var.account_id
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------
# SNS Subscription — HTTPS webhook (PendingConfirmation)
# ---------------------------------------------------------------
resource "aws_sns_topic_subscription" "https_subscription" {
  topic_arn = aws_sns_topic.critical_alerts_topic.arn
  protocol  = "https"
  endpoint  = "https://httpstat.us/200"
}

# ---------------------------------------------------------------
# SNS Subscription — Email (PendingConfirmation)
# ---------------------------------------------------------------
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.critical_alerts_topic.arn
  protocol  = "email"
  endpoint  = "oncall-soc@fico.com"
}
