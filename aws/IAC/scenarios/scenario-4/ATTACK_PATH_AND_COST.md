# Scenario 4 — Attack Path & Cost Estimation

## Attack Path

```
1. Attacker enumerates IAM roles in the account
2. Discovers: devops-s3-deploy-role (assumable by any account principal)
3. Assumes the role via sts:AssumeRole
4. Calls s3:ListAllMyBuckets → finds devops-deploy-keys-<account-id>
5. Calls s3:ListBucket → sees keys/prod-bastion-keypair.pem
6. Calls s3:GetObject → downloads the SSH private key
7. Calls ec2:DescribeInstances → finds prod-bastion-host (stopped)
8. Calls ec2:DescribeSecurityGroups → finds prod-bastion-sg with restricted CIDR
9. Calls ec2:AuthorizeSecurityGroupIngress → adds own IP to SG → DETECTION SIGNAL
10. Calls ec2:StartInstances → starts the bastion instance → DETECTION SIGNAL
11. Waits for instance to reach running state, gets public IP
12. Connects via SSH: ssh -i prod-bastion-keypair.pem ec2-user@<bastion-ip>
13. Explores the filesystem → finds:
    - /home/ec2-user/.env → DB connection string, Stripe key, Redis URL, JWT secret
    - /home/ec2-user/config/db-backup-creds.json → backup DB credentials
    - /home/ec2-user/.ssh/internal-hosts.conf → internal host IPs and usernames
    - /root/.aws/credentials → AWS ASIA session credentials
14. Attempts lateral movement to internal hosts → triggers detection
15. Attempts DB connections with extracted creds → triggers detection
16. Attempts to use AWS credentials → triggers detection
```

## AWS Resources Deployed

| Resource | Type | Pricing Model |
|----------|------|---------------|
| IAM Role + Policy | AWS::IAM::Role, AWS::IAM::Policy | Free |
| S3 Bucket + Policy | AWS::S3::Bucket, AWS::S3::BucketPolicy | Storage + requests |
| EC2 Instance (t3.nano) | AWS::EC2::Instance | On-demand hourly |
| EC2 Key Pair | Imported via deploy.sh | Free |
| Security Group | AWS::EC2::SecurityGroup | Free |
| VPC + Subnet | User-provided (parameter) | Not created by this stack |

## Monthly Cost Estimation

| Component | Estimate |
|-----------|----------|
| EC2 t3.nano (stopped, on-demand when started) | ~$0.00 (stopped) |
| EBS root volume (8 GB gp3, persists while stopped) | ~$0.64 |
| S3 storage (single PEM file, ~2 KB) | ~$0.00 |
| S3 requests | ~$0.00 |
| VPC / networking (no NAT, no ELB) | $0.00 |
| IAM resources | $0.00 |
| **Total (instance stopped)** | **~$0.64/month** |
| **Total (if attacker runs it 24/7)** | **~$4.44/month** |

The instance is deployed stopped, so you only pay for EBS storage at rest.
The attacker starting the instance is itself a detection signal (CloudTrail
logs `StartInstances`). EC2 charges only accrue while the instance is running.
