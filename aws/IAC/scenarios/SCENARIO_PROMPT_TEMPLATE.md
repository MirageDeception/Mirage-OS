# Deception Scenario Prompt Template

Copy this template, fill in the blanks, and paste it to generate a new scenario.

---

## Prompt

Create a deception scenario called `Scenario-2` using CloudFormation template.

### Lure Resources

Describe the AWS resources that form the deception chain:

- **Resource 1**: [type, name, purpose — e.g., IAM Role named `xyz` with permissions `a, b, c`]
- **Resource 2**: [type, name, purpose — e.g., S3 Bucket named `xyz` containing fake data]
- **Resource 3**: [type, name, purpose — e.g., DynamoDB table, Secrets Manager secret, SSM parameter, Lambda, etc.]
- *(add more as needed)*

### Trust / Access Model

Describe who can access the lure and how:

- [e.g., Role assumable by anyone in this account via sts:AssumeRole]
- [e.g., Bucket policy allows read from account root principal, not public]
- [e.g., Lambda triggered by CloudWatch event, reads from DynamoDB]

### Fake Data to Seed

Describe the fake data that should be placed in the lure resources:

- [e.g., Fake Terraform state file with expired credentials]
- [e.g., DynamoDB records with fake customer PII / payment tokens]
- [e.g., Secrets Manager value with fake DB connection strings]
- [e.g., S3 objects like `.env` files, config dumps, key pairs]

### Resource Naming Style

Pick names that look attractive to an attacker:

- [e.g., `prod-admin-backup`, `infra-terraform-state`, `payment-processor-keys`]
- [e.g., Tag everything with Environment=production, Project=core-platform]

### Additional Requirements

- [ ] All resources must follow security best practices (encryption, no public access, TLS-only, least privilege) to avoid standing out from real infra
- [ ] Include a `deploy.sh` bash script that deploys the stack and seeds all fake data — with comments
- [ ] Include a `README.md` explaining the deception story, resource chain, file listing, and deployment steps
- [ ] All secrets/credentials must be completely fake placeholder data (Dont use `EXPIRED` or `FAKE` prefix convention make it look legit)
- [ ] Place everything under `scenarios/[scenario-name]/`
- [ ] *(add any extra requirements here)*

---

## Output Structure

```
scenarios/[scenario-name]/
├── template.yaml          # CloudFormation template
├── deploy.sh              # Automated deploy + data seeding script
├── fake-data/             # All fake seed data files
│   ├── [file1]
│   └── [file2]
└── README.md              # Deception story, resource chain, deployment docs
```
