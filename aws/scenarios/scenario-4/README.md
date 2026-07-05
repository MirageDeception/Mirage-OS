# Scenario 4 — S3 SSH Key → EC2 Lure Bastion with Sensitive Files

## Deception Story

An attacker who gains access to the AWS account discovers an IAM role named
`devops-s3-deploy-role` — assumable by any principal in the account. The role
grants S3 read access and the ability to start/modify a specific EC2 instance.

The attacker finds an S3 bucket called `devops-deploy-keys-<account-id>` containing
an SSH private key. They discover a stopped EC2 instance tagged `prod-bastion-host`,
start it, and SSH in using the key.

On the instance they find sensitive files:

- `.env` with database connection strings, Stripe keys, Redis URLs
- DB backup credentials with replica endpoint
- Internal SSH host configuration with IPs and usernames
- AWS credentials file with session tokens

All values look legitimate. The attacker starting the instance and SSH-ing in
generates multiple CloudTrail and VPC Flow Log detection signals.

## Resource Chain

```
Attacker
  │
  ├─► Discovers IAM Role: devops-s3-deploy-role
  │     (assumable by any principal in the account)
  │
  ├─► Assumes role ─► gains S3 read + EC2 start/modify + SG modify
  │
  ├─► Finds S3 Bucket: devops-deploy-keys-<account-id>
  │     └─► Downloads keys/prod-bastion-keypair.pem
  │
  ├─► Calls ec2:DescribeInstances → finds prod-bastion-host (stopped)
  │
  ├─► Calls ec2:DescribeSecurityGroups → finds restricted SG
  │
  ├─► Calls ec2:AuthorizeSecurityGroupIngress → adds own IP → DETECTION SIGNAL
  │
  ├─► Calls ec2:StartInstances → starts the instance → DETECTION SIGNAL
  │
  └─► SSH into bastion → finds sensitive files
        │
        ├─► /home/ec2-user/.env → DB creds, Stripe key, Redis, JWT secret
        ├─► /home/ec2-user/config/db-backup-creds.json → backup DB credentials
        ├─► /home/ec2-user/.ssh/internal-hosts.conf → internal host list
        └─► /root/.aws/credentials → AWS session credentials (placeholder)
```

## Attack Path Diagram with Permissions

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                        SCENARIO 4 — SSH KEY → EC2 BASTION                                   │
│                              Attack Path + Permissions                                      │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────┐
│   ATTACKER           │
│   (any account       │
│    principal)         │
└──────────┬───────────┘
           │
           │  sts:AssumeRole
           │
           ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│  IAM ROLE: devops-s3-deploy-role                                                 │
│                                                                                  │
│  Trust Policy:                                                                   │
│    • Allow arn:aws:iam::<AccountId>:root → sts:AssumeRole                        │
│                                                                                  │
│  MaxSessionDuration: 3600s                                                       │
│  Tags: Environment=production, Project=devops-platform,                          │
│         ManagedBy=terraform, CostCenter=CC-5830                                  │
│                                                                                  │
│  Policy: devops-s3-deploy-policy                                                 │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │ [ListBuckets]          Allow s3:ListAllMyBuckets on *                      │  │
│  │ [ReadDeployKeysBucket] Allow s3:ListBucket, s3:GetObject                   │  │
│  │                        on devops-deploy-keys-<acct> + /*                   │  │
│  │ [DescribeInstances]    Allow ec2:DescribeInstances,                        │  │
│  │                              ec2:DescribeSecurityGroups on *               │  │
│  │ [ManageBastionInstance] Allow ec2:StartInstances,                          │  │
│  │                               ec2:ModifyInstanceAttribute                 │  │
│  │                         on instance/<instance-id>                          │  │
│  │ [ModifyBastionSG]      Allow ec2:AuthorizeSecurityGroupIngress,            │  │
│  │                              ec2:RevokeSecurityGroupIngress                │  │
│  │                         on security-group/<sg-id>                          │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
└───────┬──────────────────┬──────────────────────┬────────────────────────────────┘
        │                  │                      │
        │                  │                      │
        │ s3:ListAllMy     │ s3:ListBucket        │ ec2:DescribeInstances
        │ Buckets          │ s3:GetObject         │ ec2:DescribeSecurityGroups
        │ (discovery)      │                      │ (reconnaissance)
        ▼                  ▼                      ▼
┌────────────────┐  ┌──────────────────────────────────────────────────────────────┐
│ ALL S3 BUCKETS │  │  S3 BUCKET: devops-deploy-keys-<AccountId>                   │
│ (list only)    │  │                                                              │
└────────────────┘  │  Bucket Policy:                                              │
                    │  ┌────────────────────────────────────────────────────────┐   │
                    │  │ AllowRootReadAccess:                                   │   │
                    │  │   Allow <AccountId>:root → s3:GetObject, s3:ListBucket │   │
                    │  │ DenyInsecureTransport:                                 │   │
                    │  │   Deny * → s3:* if SecureTransport=false               │   │
                    │  └────────────────────────────────────────────────────────┘   │
                    │                                                              │
                    │  Protections: Versioning ✓, AES256 ✓, Public Block ✓         │
                    └──────────────────────────┬───────────────────────────────────┘
                                               │
                                               │ s3:GetObject
                                               ▼
                    ┌──────────────────────────────────────────────────────────────┐
                    │  OBJECT: keys/prod-bastion-keypair.pem                       │
                    │  (SSH private key for prod-bastion-keypair)                   │
                    └──────────────────────────┬───────────────────────────────────┘
                                               │
                                               │ Attacker now has SSH key
                                               │ but needs network access + running instance
                                               ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              ⚠️  ACTIVE ATTACK PHASE                                        │
└───────┬─────────────────────────────────────────────────────────────────┬───────────────────┘
        │                                                                 │
        │ ec2:AuthorizeSecurityGroupIngress                               │ ec2:StartInstances
        │ (add attacker's IP to SSH rule)                                 │ (boot the instance)
        ▼                                                                 ▼
┌───────────────────────────────────────────┐   ┌─────────────────────────────────────────────┐
│  SECURITY GROUP: prod-bastion-sg          │   │  EC2 INSTANCE: prod-bastion-host             │
│                                           │   │                                             │
│  Original Inbound:                        │   │  State: STOPPED → RUNNING ⚠️                │
│    • TCP 22 from 165.225.0.0/24 only      │   │  Type: t3.nano                              │
│                                           │   │  AMI: Amazon Linux 2023                     │
│  After attack:                            │   │  Key Pair: prod-bastion-keypair              │
│    • TCP 22 from 165.225.0.0/24           │   │  EBS: 8 GB gp3, encrypted                   │
│    • TCP 22 from <attacker-IP>/32 ⚠️      │   │  Subnet: public (has public IP)             │
│                                           │   │                                             │
│  Outbound: All traffic to 0.0.0.0/0      │   │  Resource Policy: ❌ None                    │
│                                           │   │  Access: IAM policy only                    │
│  Resource Policy: ❌ None                  │   │                                             │
│  Access: IAM policy only                  │   │  Tags: Environment=production,              │
│                                           │   │    Project=devops-platform, CostCenter=5830 │
└───────────────────────────────────────────┘   └──────────────────────┬──────────────────────┘
                                                                       │
                                                                       │ SSH (port 22)
                                                                       │ using prod-bastion-keypair.pem
                                                                       ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  SEEDED FILES ON INSTANCE (written by UserData at first boot)                               │
│                                                                                             │
│  ┌─────────────────────────────────┐  ┌──────────────────────────────────────────────────┐  │
│  │ /home/ec2-user/.env             │  │ /home/ec2-user/config/db-backup-creds.json       │  │
│  │  • DATABASE_URL (PostgreSQL)    │  │  • backup_host (RDS replica endpoint)            │  │
│  │  • STRIPE_SECRET_KEY (sk_live_) │  │  • username: backup_agent                       │  │
│  │  • REDIS_URL (with auth token)  │  │  • password: BkUp@g3nt#Pr0d2024xM7nQ            │  │
│  │  • JWT_SECRET                   │  │  • s3_backup_bucket: prod-db-backups-encrypted   │  │
│  └─────────────────────────────────┘  └──────────────────────────────────────────────────┘  │
│                                                                                             │
│  ┌─────────────────────────────────┐  ┌──────────────────────────────────────────────────┐  │
│  │ /home/ec2-user/.ssh/            │  │ /root/.aws/credentials                           │  │
│  │   internal-hosts.conf           │  │  • aws_access_key_id: AKIA...                    │  │
│  │  • prod-app-01 (10.0.1.101)    │  │  • aws_secret_access_key (placeholder)           │  │
│  │  • prod-app-02 (10.0.1.102)    │  │  • aws_session_token (placeholder)               │  │
│  │  • prod-db-primary (10.0.2.50) │  │  • region: us-west-2                             │  │
│  │  • prod-cache-01 (10.0.3.10)   │  │                                                  │  │
│  └─────────────────────────────────┘  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  DETECTION SIGNALS (CloudTrail + VPC Flow Logs)                                             │
│                                                                                             │
│  ⚠️  AssumeRole                     → role/devops-s3-deploy-role                            │
│  ⚠️  GetObject                      → devops-deploy-keys-<acct>/keys/prod-bastion-keypair.pem │
│  ⚠️  AuthorizeSecurityGroupIngress  → security-group/<sg-id>                               │
│  ⚠️  StartInstances                 → instance/<instance-id>                                │
│  ⚠️  SSH connection (VPC Flow Logs) → bastion public IP, port 22                           │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  COST: $0.64/mo (EBS volume only — instance is stopped)                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `template.yaml` | CloudFormation template — EC2, S3, IAM role, security group |
| `deploy.sh` | Deploy script — generates SSH key, deploys stack, stops instance, uploads key to S3 |
| `destroy.sh` | Teardown script — empties bucket, deletes stack, removes key pair and local files |
| `keys/` | SSH key pair (generated by deploy.sh) |

## Security Best Practices Applied

- S3 public access fully blocked (all four PublicAccessBlock settings)
- Bucket encryption enabled (AES256 with bucket key)
- Versioning enabled on the bucket
- TLS-only access enforced via bucket policy
- EBS volume encrypted
- Security group restricts SSH to deployer-specified CIDR (default 165.225.0.0/24)
- Attacker must modify SG to add their IP (another CloudTrail detection signal)
- SG modify permissions scoped to the specific security group only
- EC2 start/modify permissions scoped to the specific instance ARN
- S3 read permissions scoped to the specific bucket
- Instance deployed stopped — attacker must start it (detection signal)
- No instance profile by default — scenario-5 can attach one

## Deployment

### Quick deploy (recommended)

```bash
chmod +x deploy.sh
./deploy.sh
```

Override region:

```bash
AWS_DEFAULT_REGION=eu-west-1 ./deploy.sh
```

### Teardown

```bash
chmod +x destroy.sh
./destroy.sh
```

This handles everything: empties the versioned S3 bucket, deletes the CloudFormation stack, removes the EC2 Key Pair, and cleans up local key files.

### What the script does

1. Lists VPCs in the region — user picks one
2. Lists subnets in the chosen VPC — user picks one
3. Prompts for SSH allowed CIDR (default: 165.225.0.0/24)
4. Generates a 4096-bit RSA key pair
5. Imports the public key as an EC2 Key Pair
6. Deploys the CloudFormation stack into the chosen VPC/subnet
7. Stops the EC2 instance immediately after launch
8. Uploads the private key to the S3 lure bucket

## Extending with Scenario 5

Scenario 5 (ECR lure) can attach an instance profile to this bastion,
creating a multi-hop attack chain: S3 → EC2 → ECR. Deploy scenario-5
after this one and it will automatically detect and link to this instance.

## Customization

- Edit the UserData section in `template.yaml` to change the sensitive files
  seeded on the instance
- Replace the PLACEHOLDER values in `/root/.aws/credentials` with your own
  fake ASIA session tokens after deployment
