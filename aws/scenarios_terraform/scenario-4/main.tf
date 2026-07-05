data "aws_region" "current" {}

resource "aws_security_group" "bastion_security_group" {
  name        = "prod-bastion-sg"
  description = "SSH access for production bastion host"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "prod-bastion-sg"
    Environment = "production"
    Project     = "devops-platform"
    ManagedBy   = "terraform"
  }
}

resource "aws_network_interface" "bastion_eni" {
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.bastion_security_group.id]
  description     = "Primary network interface for bastion host"
  
  # Note: AssociatePublicIpAddress is typical for bastions, usually handled via subnet config or EIP
}

resource "aws_instance" "bastion_instance" {
  ami           = var.ami_id
  instance_type = "t4g.nano"
  key_name      = var.key_pair_name

  network_interface {
    network_interface_id = aws_network_interface.bastion_eni.id
    device_index         = 0
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
set -e

# --- Seed .env with database and API credentials ---
cat > /home/ec2-user/.env << 'ENVEOF'
DATABASE_URL=postgresql://payments_admin:Kj8#mR2xVn5qW9tL@prod-payments-db.c9aksj2e7rzo.us-west-2.rds.amazonaws.com:5432/payments_prod
STRIPE_SECRET_KEY=sk_live_51NxGr7eD48IqMzkXEbsjT2ze1qp8dc
REDIS_URL=redis://:r3d1s_pr0d_t0k3n_8xK2mV@prod-payments-cache.eabc12.0001.usw2.cache.amazonaws.com:6379/0
JWT_SECRET=jwtS1gn1ng_s3cr3t_pr0d_7fA9bC1dE3
AWS_DEFAULT_REGION=us-west-2
ENVEOF
chown ec2-user:ec2-user /home/ec2-user/.env
chmod 600 /home/ec2-user/.env

# --- Seed DB backup credentials ---
mkdir -p /home/ec2-user/config
cat > /home/ec2-user/config/db-backup-creds.json << 'DBEOF'
{
  "backup_host": "prod-payments-db-replica.c9aksj2e7rzo.us-west-2.rds.amazonaws.com",
  "port": 5432,
  "username": "backup_agent",
  "password": "BkUp@g3nt#Pr0d2024xM7nQ",
  "database": "payments_prod",
  "s3_backup_bucket": "prod-db-backups-encrypted",
  "schedule": "daily 02:00 UTC"
}
DBEOF
chown -R ec2-user:ec2-user /home/ec2-user/config
chmod 600 /home/ec2-user/config/db-backup-creds.json

# --- Seed internal SSH hosts config ---
mkdir -p /home/ec2-user/.ssh
cat > /home/ec2-user/.ssh/internal-hosts.conf << 'SSHEOF'
# Production internal hosts — managed by Ansible
Host prod-app-01
    HostName 10.0.1.101
    User deploy
Host prod-app-02
    HostName 10.0.1.102
    User deploy
Host prod-db-primary
    HostName 10.0.2.50
    User dbadmin
Host prod-cache-01
    HostName 10.0.3.10
    User redis
SSHEOF
chown ec2-user:ec2-user /home/ec2-user/.ssh/internal-hosts.conf
chmod 600 /home/ec2-user/.ssh/internal-hosts.conf

# --- Seed AWS credentials placeholder ---
mkdir -p /root/.aws
cat > /root/.aws/credentials << 'AWSEOF'
[default]
aws_access_key_id = ASIAPLACHOLDER000001
aws_secret_access_key = PLACEHOLDER_SECRET_KEY_FILL_LATER
aws_session_token = PLACEHOLDER_SESSION_TOKEN_FILL_LATER
region = us-west-2
AWSEOF
chmod 600 /root/.aws/credentials
EOF
  )

  tags = {
    Name        = "prod-bastion-host"
    Environment = "production"
    Project     = "devops-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-5830"
  }
}

resource "aws_iam_role" "devops_s3_deploy_role" {
  name                 = "devops-s3-deploy-role"
  description          = "Read access to deployment keys bucket and bastion instance management"
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
    Project     = "devops-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-5830"
  }
}

resource "aws_iam_policy" "devops_s3_deploy_policy" {
  name = "devops-s3-deploy-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadDeployKeysBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.deploy_keys_bucket.arn,
          "${aws_s3_bucket.deploy_keys_bucket.arn}/*"
        ]
      },
      {
        Sid    = "DescribeInstances"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageBastionInstance"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:ModifyInstanceAttribute"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${var.account_id}:instance/${aws_instance.bastion_instance.id}"
      },
      {
        Sid    = "ModifyBastionSecurityGroup"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${var.account_id}:security-group/${aws_security_group.bastion_security_group.id}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "devops_s3_deploy_policy_attach" {
  role       = aws_iam_role.devops_s3_deploy_role.name
  policy_arn = aws_iam_policy.devops_s3_deploy_policy.arn
}

resource "aws_s3_bucket" "deploy_keys_bucket" {
  bucket = "devops-deploy-keys-${var.account_id}"

  tags = {
    Environment = "production"
    Project     = "devops-platform"
    ManagedBy   = "terraform"
    CostCenter  = "CC-5830"
  }
}

resource "aws_s3_bucket_versioning" "deploy_keys_bucket_versioning" {
  bucket = aws_s3_bucket.deploy_keys_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deploy_keys_bucket_encryption" {
  bucket = aws_s3_bucket.deploy_keys_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "deploy_keys_bucket_pab" {
  bucket = aws_s3_bucket.deploy_keys_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "deploy_keys_bucket_lifecycle" {
  bucket = aws_s3_bucket.deploy_keys_bucket.id

  rule {
    id     = "AbortIncompleteMultipartUploads"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "deploy_keys_bucket_policy" {
  bucket = aws_s3_bucket.deploy_keys_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootReadAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.deploy_keys_bucket.arn,
          "${aws_s3_bucket.deploy_keys_bucket.arn}/*"
        ]
      },
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.deploy_keys_bucket.arn,
          "${aws_s3_bucket.deploy_keys_bucket.arn}/*"
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
