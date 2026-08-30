# Mirage | Enterprise Deception Fabric

Mirage is an automated, scalable enterprise deception platform designed to deploy Honey Attack Paths (decoy infrastructure) across your AWS Spoke accounts. It automatically routes threat telemetry back to a centralized Hub account to detect lateral movement.

## Platform Walkthrough

### 1. Dashboard, Active Alerts & Settings
*Note: These features are currently in progress but the foundational UI and routing are established.*
- **Dashboard:** Will provide a birds-eye view of your deception coverage and footprint across all Spoke accounts.
- **Active Alerts:** The future home for real-time lateral movement detection alerts parsed from incoming EventBridge telemetry.
- **Settings:** Global configuration for UI preferences, SSO/Authentication, and centralized backend states.

### 2. Deploy Brain & Remove Brain
The "Brain" refers to the core deception infrastructure deployed in your primary security/logging account. Once a Brain deployment is initiated, the platform automatically provisions the following critical architecture components:

- **Global EventBus (`Mirage-Hub-Bus`):** A centralized AWS EventBridge bus that acts as the primary ingress point for cross-account threat telemetry coming from all your Spoke accounts.
- **Event Processor (AWS Lambda):** A serverless engine that continuously listens to the Global EventBus. It parses raw incoming CloudTrail events, maps them against your active decoy inventory, and formats them into high-fidelity security alerts.
- **Alert Dispatcher (Amazon SNS):** An SNS topic (`Mirage-Alerts`) that instantly pushes the processed alerts from the Lambda function to your configured endpoints (e.g., Enterprise Slack webhooks, PagerDuty, or analyst email addresses).
- **Cross-Account Trust Policies:** Auto-generated resource-based policies that grant strict, least-privilege permissions for your Spoke accounts to forward telemetry into the Brain.

#### The Dual-Tier Telemetry Filtering System
To prevent the Brain from being overwhelmed by billions of standard AWS API calls, Mirage utilizes a highly efficient **dual-tier filtering architecture**:
1. **Tier 1 (The Spoke Account):** When a scenario is deployed, Mirage generates a highly specific EventBridge rule in the local Spoke account. This rule filters CloudTrail events so that **only** API calls interacting directly with the exact decoy resources are forwarded to the Brain.
2. **Tier 2 (The Hub/Brain Account):** When deploying the Brain, Mirage provisions static, service-specific EventBridge rules on the Global EventBus. These rules act as the second layer of filtering—listening to the incoming telemetry and ensuring the Lambda processor is only triggered for specific, highly sensitive API actions. 

Here are the specific service-wise rules and events monitored at Tier 2:

| AWS Service | Monitored CloudTrail Events (Tier 2 Filtering) |
| :--- | :--- |
| **S3** | `GetObject`, `ListBucket`, `DeleteBucket`, `PutObject` |
| **Secrets Manager** | `GetSecretValue`, `DescribeSecret` |
| **SSM Parameter Store** | `GetParameter`, `GetParameters`, `GetParametersByPath` |
| **STS** | `AssumeRole`, `AssumeRoleWithSAML` |
| **EC2** | `StartInstances`, `AuthorizeSecurityGroupIngress`, `DescribeInstances` |
| **ECR** | `BatchGetImage`, `GetDownloadUrlForLayer` |
| **Lambda** | `GetFunctionConfiguration`, `GetFunction` |
| **DynamoDB** | `DescribeTable`, `Scan`, `Query`, `GetItem` |
| **SQS** | `GetQueueAttributes`, `ReceiveMessage` |
| **SNS** | `GetTopicAttributes`, `ListSubscriptionsByTopic`, `Publish` |
| **CloudWatch Logs** | `GetLogEvents`, `FilterLogEvents` |
| **KMS** | `DescribeKey`, `Decrypt` |
| **IAM** | `GetSAMLProvider`, `ListUsers`, `ListRoles` |
| **CloudFormation** | `DescribeStacks`, `GetTemplate` |

To deploy or remove the Brain, you must provide:
- **Target Account ID:** The AWS Account ID where the central hub should live.
- **Deployment Role ARN:** The IAM Role that Mirage will assume to execute the Terraform deployment.
- *(Optional) SNS Subscriptions:* Webhook URLs or email addresses to automatically subscribe to the Alert Dispatcher.

### 3. Deception Catalog
The Catalog is the heart of Mirage. It contains pre-built deception scenarios (Attack Paths). 

#### Customizing Scenarios
The scenarios in the catalog are fetched dynamically from a connected GitHub repository (`MirageDeception/Mirage-OS`). The underlying decoy resources (like S3 bucket names, IAM role names, and Secrets) can be seamlessly renamed so they blend perfectly into your organization's specific AWS environment naming conventions.

**How to rename resources:**
1. Navigate to the scenario's Terraform template folder in the GitHub repo (e.g., `src/templates/mirage-os/aws/scenarios_terraform/scenario-1`).
2. Open the `variables.tf` file.
3. Modify the default values or structural names. 

**Example:**
If you want to rename the fake S3 bucket in Scenario 1 to look like a highly sensitive payroll bucket:
```hcl
variable "bucket_name" {
  description = "The name of the decoy S3 bucket"
  type        = string
  default     = "finance-payroll-backup-prod" # Change this to blend into your org!
}
```
After committing this change to the master branch in GitHub, the Mirage portal will automatically sync the changes. The next time you load the portal, the catalog will instantly reflect the new infrastructure parameters!

#### Deploying Decoys
To deploy a scenario, fill out the **Global Spoke Auth** panel at the top right of the Catalog:
- **Spoke Account ID:** The target AWS account where the decoys will live.
- **Spoke Deployment Role:** The IAM Role assumed to run Terraform (e.g., `arn:aws:iam::123456789012:role/SpokeDeployRole`).
- **Hub EventBus Target:** The central bus receiving the telemetry in your Brain account (e.g., `arn:aws:events:us-east-1:098765432109:event-bus/HubBus`).
- **EventBridge Forwarding Role:** The role allowing the Spoke account to dispatch events to the Hub.

Select the checkboxes for the scenarios you want and hit **Deploy Selected**.

### 4. Automated Rule Generation
Mirage doesn't just deploy infrastructure; it completely automates the complex telemetry routing. 
When a scenario is deployed, Mirage reads the Terraform state outputs to discover the exact names of the newly created decoy resources. It currently supports automated rule generation for high-value targets including: **IAM, S3, Secrets Manager, DynamoDB, Lambda, SSM, ECR, KMS, SQS, and SNS**.

It then dynamically generates an **AWS EventBridge Rule** that filters AWS CloudTrail events for malicious API calls made specifically against those decoy resources.

**Rule Management Modes:**
Mirage offers two distinct methods for managing these EventBridge rules (toggled via a switch in the UI):
1. **Individual Rules:** A dedicated EventBridge rule is created for *each* scenario. This isolates telemetry cleanly but consumes more AWS account rule quotas.
2. **Bin-Packing (Scale Mode):** Decoys are appended to a single, monolithic EventBridge rule. Mirage meticulously tracks the strict AWS character limits for JSON event patterns. When a rule reaches capacity, the system automatically overflows and provisions a new rule!
   - *Self-Healing Updates:* If you teardown/remove a scenario from AWS, Mirage automatically parses the active rule, surgically strips out the deleted decoys from the JSON pattern, and patches the rule in AWS.

### 5. Active Rules & Scenario Review
- **Active Rules Tab:** View all generated EventBridge rules and their current JSON event patterns. When deploying or tearing down scenarios in Bin-Packing mode, Mirage allows you to review the exact JSON diff (additions in green, removals in red) of how the EventBridge pattern will change *before* you push the update to AWS!
- **Active Scenarios Tab:** A comprehensive inventory tracking exactly which scenarios are deployed in which Spoke accounts, including their deployment timestamps and custom parameters. 

### 6. History & Notifications
Total observability is built directly into the UI.
- **History Tab:** An audit log tracking the success or failure of every single Terraform deployment, teardown, rule generation, and trust policy update across your fleet.
- **Activity Feed (Bell Icon):** Real-time, color-coded notifications drop down from the top right corner. You'll be instantly alerted to GitHub catalog syncs, deployment statuses, and even exact backend Terraform error messages if an AWS deployment fails.

### 7. State Management & Local Databases
Mirage utilizes a lightweight, flat-file state management system to track deployments, EventBridge rules, and decoy inventories without requiring a heavy external database. 

**Database Files:**
- `db_inventory.txt`: A ledger that meticulously tracks every single decoy deployed across your entire Spoke fleet, mapping the AWS Account ID, Scenario ID, Target Rule, Decoy Name, and Decoy Category. This powers the automated rule maintenance and teardown processes.
- `db_rules.json`: Tracks the state of all generated EventBridge rules, including their exact JSON character count to intelligently manage strict AWS quota limits.
- `db_history.json`: Stores the audit log of all actions taken within the portal.

> [!IMPORTANT]
> **For First-Time Users:** 
> When you first clone this repository, you will notice these files are missing (they are explicitly ignored in `.gitignore` to prevent leaking infrastructure state to public repositories). **You do not need to create them manually.** The Mirage backend is built with self-healing initialization; the very first time you boot the portal or execute a deployment, the system will automatically generate pristine, empty files with the exact names and data structures required!
