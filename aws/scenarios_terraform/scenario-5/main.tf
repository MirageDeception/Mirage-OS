data "aws_region" "current" {}

resource "aws_iam_role" "bastion_ecr_role" {
  name                 = var.role_name
  description          = "ECR read access for production bastion host container operations"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "production"
    Project     = "payment-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-5830"
  }
}

resource "aws_iam_policy" "bastion_ecr_policy" {
  name = "prod-bastion-ecr-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcrAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "EcrReadRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = aws_ecr_repository.payment_service_repo.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ecr_policy_attach" {
  role       = aws_iam_role.bastion_ecr_role.name
  policy_arn = aws_iam_policy.bastion_ecr_policy.arn
}

resource "aws_iam_instance_profile" "bastion_instance_profile" {
  name = "${var.role_name}-profile"
  role = aws_iam_role.bastion_ecr_role.name
}

resource "aws_ecr_repository" "payment_service_repo" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "production"
    Project     = "payment-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-5830"
  }
}

resource "aws_ecr_repository_policy" "payment_service_repo_policy" {
  repository = aws_ecr_repository.payment_service_repo.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
      }
    ]
  })
}
