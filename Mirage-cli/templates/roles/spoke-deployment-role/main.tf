terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────
# IAM Role — mirage-deployment-role
#   Trust: Hub account + ExternalId (prevents confused deputy)
#   Permission: Managed policy for deception resource deployment
#   Boundary: Prevents IAM privilege escalation
# ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "mirage_deployment" {
  name                 = var.deployment_role_name
  description          = "Mirage CLI: assumed by hub to deploy deception resources in this spoke"
  max_session_duration = 3600
  path                 = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MirageHubAssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.hub_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })

  tags = {
    Name          = var.deployment_role_name
    ManagedBy     = "mirage"
    SpokeAlias    = var.spoke_alias
    DeceptionRole = "deployment"
  }
}

# Inline policy — covers all 19 AWS deception scenarios.
resource "aws_iam_role_policy" "mirage_deployment_permissions" {
  name = "mirage-deception-deployment"
  role = aws_iam_role.mirage_deployment.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DeceptionResourceDeployment"
        Effect = "Allow"
        Action = [
          # S3 (scenarios 1, 3, 4)
          "s3:CreateBucket", "s3:DeleteBucket",
          "s3:PutBucketPolicy", "s3:GetBucketPolicy",
          "s3:PutBucketVersioning", "s3:PutBucketEncryption",
          "s3:PutPublicAccessBlock", "s3:GetBucketLocation",
          "s3:PutObject", "s3:DeleteObject", "s3:GetObject",
          "s3:ListBucket", "s3:PutLifecycleConfiguration",
          # IAM (all scenarios)
          "iam:CreateRole", "iam:DeleteRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:CreatePolicy", "iam:DeletePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:GetRole", "iam:ListRoles", "iam:ListAttachedRolePolicies",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfiles", "iam:PassRole",
          "iam:TagRole", "iam:UntagRole",
          # Secrets Manager (scenario 2)
          "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret",
          "secretsmanager:PutSecretValue", "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret", "secretsmanager:TagResource",
          "secretsmanager:RestoreSecret",
          # SSM (scenarios 3, 8, 16, 18, 19)
          "ssm:PutParameter", "ssm:DeleteParameter", "ssm:GetParameter",
          "ssm:GetParameters", "ssm:AddTagsToResource",
          "ssm:DescribeParameters",
          # EC2 (scenario 4)
          "ec2:RunInstances", "ec2:TerminateInstances",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeInstances", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets", "ec2:DescribeVpcs",
          "ec2:CreateTags", "ec2:DeleteTags",
          # ECR (scenario 5)
          "ecr:CreateRepository", "ecr:DeleteRepository",
          "ecr:SetRepositoryPolicy", "ecr:GetRepositoryPolicy",
          "ecr:TagResource",
          # Lambda (scenarios 6, 7, 17)
          "lambda:CreateFunction", "lambda:DeleteFunction",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction", "lambda:AddPermission", "lambda:RemovePermission",
          "lambda:TagResource",
          # DynamoDB (scenarios 9, 10, 17)
          "dynamodb:CreateTable", "dynamodb:DeleteTable",
          "dynamodb:PutItem", "dynamodb:GetItem",
          "dynamodb:DescribeTable", "dynamodb:UpdateTable",
          "dynamodb:TagResource",
          # SQS (scenario 11)
          "sqs:CreateQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes",
          "sqs:GetQueueAttributes", "sqs:SendMessage", "sqs:TagQueue",
          # SNS (scenario 12)
          "sns:CreateTopic", "sns:DeleteTopic",
          "sns:SetTopicAttributes", "sns:GetTopicAttributes",
          "sns:Subscribe", "sns:Unsubscribe", "sns:TagResource",
          # CloudWatch Logs (scenario 13)
          "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy", "logs:PutLogEvents",
          "logs:CreateLogStream", "logs:TagLogGroup",
          # KMS (scenario 14)
          "kms:CreateKey", "kms:ScheduleKeyDeletion",
          "kms:CreateAlias", "kms:DeleteAlias",
          "kms:GetKeyPolicy", "kms:PutKeyPolicy",
          "kms:DescribeKey", "kms:TagResource",
          # CloudFormation (scenario 19)
          "cloudformation:CreateStack", "cloudformation:DeleteStack",
          "cloudformation:DescribeStacks", "cloudformation:UpdateStack",
          "cloudformation:CreateChangeSet", "cloudformation:DeleteChangeSet",
          # EventBridge (forwarding rules for monitor)
          "events:PutRule", "events:DeleteRule",
          "events:PutTargets", "events:RemoveTargets",
          "events:DescribeRule",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyEscalation"
        Effect = "Deny"
        Action = [
          "iam:CreateLoginProfile",
          "iam:UpdateLoginProfile",
          "iam:AttachUserPolicy",
          "iam:CreateUser",
          "iam:DeleteUser",
        ]
        Resource = "*"
      }
    ]
  })
}
