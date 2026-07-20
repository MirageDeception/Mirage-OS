resource "aws_iam_role" "payment_secrets_readonly_role" {
  name                 = var.role_name
  description          = "Read-only access to payment gateway secrets for backend services"
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
    CostCenter  = "CC-7192"
  }
}

resource "aws_iam_policy" "payment_secrets_policy" {
  name = "payment-secrets-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListAllSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadPaymentSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.stripe_keys_secret.arn,
          aws_secretsmanager_secret.braintree_credentials_secret.arn,
          aws_secretsmanager_secret.service_accounts_secret.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "payment_secrets_policy_attach" {
  role       = aws_iam_role.payment_secrets_readonly_role.name
  policy_arn = aws_iam_policy.payment_secrets_policy.arn
}

resource "aws_secretsmanager_secret" "stripe_keys_secret" {
  name        = var.stripe_secret_name
  description = "Stripe live-mode API keys for production payment processing"
  tags = {
    Environment      = "production"
    Project          = "payment-platform"
    ManagedBy        = "terraform"
    CostCenter       = "CC-7192"
    RotationSchedule = "90days"
  }
}

resource "aws_secretsmanager_secret_version" "stripe_keys_secret_version" {
  secret_id     = aws_secretsmanager_secret.stripe_keys_secret.id
  secret_string = jsonencode({ "placeholder" : "replaced-by-deploy-script" })
}

resource "aws_secretsmanager_secret_policy" "stripe_keys_resource_policy" {
  secret_arn = aws_secretsmanager_secret.stripe_keys_secret.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountRead"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "braintree_credentials_secret" {
  name        = var.braintree_secret_name
  description = "Braintree merchant credentials for production payment fallback processor"
  tags = {
    Environment      = "production"
    Project          = "payment-platform"
    ManagedBy        = "terraform"
    CostCenter       = "CC-7192"
    RotationSchedule = "90days"
  }
}

resource "aws_secretsmanager_secret_version" "braintree_credentials_secret_version" {
  secret_id     = aws_secretsmanager_secret.braintree_credentials_secret.id
  secret_string = jsonencode({ "placeholder" : "replaced-by-deploy-script" })
}

resource "aws_secretsmanager_secret_policy" "braintree_credentials_resource_policy" {
  secret_arn = aws_secretsmanager_secret.braintree_credentials_secret.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountRead"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "service_accounts_secret" {
  name        = var.service_accounts_secret_name
  description = "Shared service account credentials for inter-service authentication"
  tags = {
    Environment = "production"
    Project     = "payment-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-7192"
  }
}

resource "aws_secretsmanager_secret_version" "service_accounts_secret_version" {
  secret_id     = aws_secretsmanager_secret.service_accounts_secret.id
  secret_string = jsonencode({ "placeholder" : "replaced-by-deploy-script" })
}

resource "aws_secretsmanager_secret_policy" "service_accounts_resource_policy" {
  secret_arn = aws_secretsmanager_secret.service_accounts_secret.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountRead"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}
