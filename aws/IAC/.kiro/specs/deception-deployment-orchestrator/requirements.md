# Requirements Document

## Introduction

This feature builds a deployment orchestrator that manages the deployment of deception scenarios across 100+ AWS accounts in an AWS Organization. The orchestrator selects scenarios per account using a tiered strategy (core always-deploy + random-select), generates realistic randomized resource names that blend with each account's environment, deploys scenario CloudFormation stacks via cross-account IAM roles, and maintains a central deployment manifest in DynamoDB. The monitoring stack (separate spec) consumes this manifest at runtime to configure its detection rules with the randomized names.

The orchestrator is a Python CLI tool that runs from the security account (or management account), uses boto3 with STS AssumeRole for cross-account operations, and supports deploy, teardown, dry-run, and status commands. Name randomization uses a deterministic seed per account so re-running produces identical names. Each scenario is deployed as a separate CloudFormation stack in the member account, with randomized resource names passed as CloudFormation parameter overrides.

## Glossary

- **Orchestrator**: The Python CLI tool that manages deception scenario deployment across all Member_Accounts from the Security_Account.
- **Security_Account**: The designated AWS account that hosts the orchestrator, the Deployment_Manifest DynamoDB table, and the centralized monitoring pipeline.
- **Member_Account**: Any AWS account in the organization where deception scenarios are deployed.
- **Deployment_Manifest**: A DynamoDB table in the Security_Account that tracks which scenarios are deployed in which accounts with which randomized resource names.
- **Scenario_Template**: A CloudFormation template in `scenarios/scenario-N/template.yaml` that defines the resources for a single deception scenario.
- **Core_Scenario**: One of the four always-deploy scenarios (1, 2, 3, 8) that are deployed to every Member_Account.
- **Random_Scenario**: A scenario from the random-select pool (scenarios 4–7, 9–19) that may be randomly selected for deployment to a Member_Account.
- **Naming_Theme**: A coherent set of realistic naming patterns (prefixes, team names, service names) assigned to a Member_Account and used consistently across all scenarios deployed in that account.
- **Resource_Map**: A mapping of original resource names (as defined in Scenario_Templates) to randomized resource names for a specific account and scenario.
- **Role_Map**: A mapping of original IAM role names to randomized IAM role names for a specific account and scenario.
- **Deployment_Role**: A pre-provisioned IAM role in each Member_Account that the Orchestrator assumes to deploy CloudFormation stacks. Provisioned via a separate StackSet.
- **Deterministic_Seed**: A value derived from the account ID (and optionally a global salt) used to seed the random number generator, ensuring the same account always receives the same scenario selection and naming theme.
- **Dry_Run**: An execution mode where the Orchestrator computes and displays the full deployment plan (scenario selection, name randomization, stack parameters) without creating or modifying any AWS resources.
- **Deployment_Status**: The state of a scenario deployment in a Member_Account: PENDING, DEPLOYED, FAILED, or DELETED.
- **Parameter_Override**: A CloudFormation parameter value passed during stack creation that overrides a default value in the Scenario_Template, used to inject randomized resource names.

## Requirements

### Requirement 1: Tiered Scenario Selection

**User Story:** As a security engineer, I want each member account to receive a mix of always-deploy core scenarios and randomly selected additional scenarios, so that every account has baseline deception coverage while maintaining variety across the organization.

#### Acceptance Criteria

1. THE Orchestrator SHALL deploy Core_Scenarios 1 (S3 Terraform State Lure), 2 (Payment Credentials), 3 (Infrastructure Vault), and 8 (Role Chain Loop) to every Member_Account.
2. THE Orchestrator SHALL randomly select 0 to 4 additional Random_Scenarios from the pool of scenarios 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, and 19 for each Member_Account.
3. THE Orchestrator SHALL deploy between 4 and 8 total scenarios (inclusive) to each Member_Account.
4. WHEN the Orchestrator selects Random_Scenarios for a Member_Account, THE Orchestrator SHALL use a Deterministic_Seed derived from the account ID so that re-running the Orchestrator produces the same scenario selection for the same account.
5. THE Orchestrator SHALL produce different scenario selections across different Member_Accounts to avoid a uniform deployment pattern across the organization.

### Requirement 2: Deterministic Name Randomization Engine

**User Story:** As a security engineer, I want each account's deception resources to have unique, realistic names that blend with production infrastructure, so that attackers cannot identify decoy resources by recognizing a naming pattern shared across accounts.

#### Acceptance Criteria

1. THE Orchestrator SHALL maintain a pool of realistic naming patterns for each resource type, including S3 bucket prefixes (e.g., `infra-`, `platform-`, `data-`, `ops-`), IAM role name patterns (e.g., `{team}-{service}-readonly-role`), SSM parameter path prefixes, Secrets Manager secret path prefixes, DynamoDB table name patterns, Lambda function name patterns, and other service-specific naming conventions.
2. WHEN the Orchestrator generates names for a Member_Account, THE Orchestrator SHALL select a Naming_Theme for the account and apply the theme consistently across all scenarios deployed in that account.
3. THE Orchestrator SHALL use a Deterministic_Seed derived from the account ID so that re-running the Orchestrator produces the same randomized names for the same account.
4. THE Orchestrator SHALL produce randomized names that appear realistic and production-like, containing no random character strings, no obvious sequential patterns, and no identifiers that reveal the resource as a decoy.
5. THE Orchestrator SHALL produce different Naming_Themes across different Member_Accounts so that no two accounts share the same set of resource names.
6. THE Orchestrator SHALL generate a Resource_Map (original name to randomized name) and a Role_Map (original role name to randomized role name) for each scenario deployed in each account.
7. FOR ALL valid account IDs, generating names then regenerating names with the same Deterministic_Seed SHALL produce identical Resource_Maps and Role_Maps (round-trip determinism property).

### Requirement 3: Parameterized Scenario Templates

**User Story:** As a security engineer, I want scenario CloudFormation templates to accept resource names as parameters, so that the orchestrator can inject randomized names without modifying the template files.

#### Acceptance Criteria

1. THE Orchestrator SHALL add CloudFormation parameters to each Scenario_Template for all resource names that require randomization, including IAM role names, S3 bucket name prefixes, Secrets Manager secret name paths, SSM parameter name paths, DynamoDB table names, Lambda function names, SQS queue names, SNS topic names, KMS key alias names, SAML provider names, CloudWatch log group names, CloudFormation stack display names, and ECR repository names.
2. WHEN deploying a scenario, THE Orchestrator SHALL pass the randomized names as Parameter_Overrides to the CloudFormation CreateStack or UpdateStack API call.
3. THE Scenario_Templates SHALL retain their original hardcoded names as default parameter values so that standalone deployment without the Orchestrator continues to function.
4. THE Orchestrator SHALL validate that every resource name referenced in a Scenario_Template has a corresponding parameter before deployment.

### Requirement 4: Cross-Account Deployment

**User Story:** As a security engineer, I want the orchestrator to deploy scenario stacks into member accounts by assuming a cross-account role, so that I can manage deception deployments centrally from the security account.

#### Acceptance Criteria

1. WHEN deploying to a Member_Account, THE Orchestrator SHALL assume the Deployment_Role in the target account using STS AssumeRole.
2. THE Orchestrator SHALL use the assumed role credentials to call CloudFormation CreateStack in the target Member_Account.
3. THE Orchestrator SHALL deploy each scenario as a separate CloudFormation stack in the Member_Account, using a stack name that includes the scenario number and a deployment identifier.
4. IF the Deployment_Role does not exist or the AssumeRole call fails for a Member_Account, THEN THE Orchestrator SHALL log the error, record the Deployment_Status as FAILED for that account, and continue processing remaining accounts.
5. THE Orchestrator SHALL support deploying to a single account (by account ID), a list of accounts (by account IDs), or all accounts in the organization (by querying AWS Organizations ListAccounts).
6. WHEN deploying to all accounts in the organization, THE Orchestrator SHALL exclude the Security_Account and the management account from the deployment target list.

### Requirement 5: Deployment Manifest (DynamoDB)

**User Story:** As a security engineer, I want a central registry that tracks which account has which scenarios with which randomized names, so that the monitoring stack can resolve randomized names back to scenario numbers at runtime.

#### Acceptance Criteria

1. THE Orchestrator SHALL create and maintain a DynamoDB table named `deception-deployment-manifest` in the Security_Account with partition key `account_id` (String) and sort key `scenario_number` (Number).
2. WHEN a scenario is deployed to a Member_Account, THE Orchestrator SHALL write a record to the Deployment_Manifest containing: `account_id`, `scenario_number`, `scenario_name` (human-readable), `stack_name` (CloudFormation stack name in the member account), `deployed_at` (ISO 8601 timestamp), `naming_theme` (the Naming_Theme identifier used for the account), `resource_map` (Map of original name to randomized name), `role_map` (Map of original role name to randomized role name), `status` (Deployment_Status), and `region` (AWS region).
3. WHEN a scenario deployment succeeds, THE Orchestrator SHALL set the Deployment_Status to DEPLOYED.
4. WHEN a scenario deployment fails, THE Orchestrator SHALL set the Deployment_Status to FAILED and include the error message in the record.
5. WHEN a scenario is torn down from a Member_Account, THE Orchestrator SHALL set the Deployment_Status to DELETED and retain the record for audit purposes.
6. THE Deployment_Manifest DynamoDB table SHALL use on-demand (PAY_PER_REQUEST) billing mode.
7. THE Orchestrator SHALL support querying the Deployment_Manifest by account_id to retrieve all scenarios deployed in a specific account.

### Requirement 6: Monitoring Stack Integration

**User Story:** As a security engineer, I want the monitoring stack's Detection Lambda to read the deployment manifest at runtime, so that it can resolve randomized resource names back to scenario numbers without requiring per-account Lambda code generation.

#### Acceptance Criteria

1. THE Deployment_Manifest SHALL serve as the interface between the Orchestrator and the monitoring stack, providing the mapping from randomized resource names to scenario numbers.
2. THE Deployment_Manifest records SHALL contain sufficient information for the Detection_Lambda to match a CloudTrail event's resource name against the Resource_Map and Role_Map to identify the corresponding scenario number.
3. WHEN the Orchestrator updates the Deployment_Manifest (deploy, teardown, or redeploy), THE Orchestrator SHALL write the updated records atomically per scenario to prevent partial reads by the Detection_Lambda.
4. THE Orchestrator SHALL generate an EventBridge forwarding rule configuration per account that matches on the randomized role names and resource names instead of the original hardcoded names.
5. THE Orchestrator SHALL generate Advanced Event Selector configurations per account that scope data event logging to the randomized S3 bucket names, DynamoDB table names, SQS queue names, and CloudWatch log group names.

### Requirement 7: CLI Interface

**User Story:** As a security engineer, I want a command-line interface with deploy, teardown, dry-run, status, and list commands, so that I can manage deception deployments efficiently.

#### Acceptance Criteria

1. THE Orchestrator SHALL provide a `deploy` command that selects scenarios, generates randomized names, deploys CloudFormation stacks, and updates the Deployment_Manifest for the specified target accounts.
2. THE Orchestrator SHALL provide a `teardown` command that deletes all deception CloudFormation stacks from the specified target accounts and updates the Deployment_Manifest status to DELETED.
3. THE Orchestrator SHALL provide a `dry-run` command that computes and displays the full deployment plan (scenario selection, randomized names, stack parameters, CloudFormation template changes) without creating or modifying any AWS resources or Deployment_Manifest records.
4. THE Orchestrator SHALL provide a `status` command that queries the Deployment_Manifest and displays the current deployment state for the specified target accounts, including scenario numbers, stack names, deployment timestamps, and statuses.
5. THE Orchestrator SHALL provide a `list` command that displays all 19 available scenarios with their numbers, names, descriptions, tier (core or random), and AWS services used.
6. THE Orchestrator SHALL accept a `--account` flag to target a single account, an `--accounts` flag to target a comma-separated list of accounts, and an `--all` flag to target all accounts in the organization.
7. THE Orchestrator SHALL accept a `--region` flag to specify the deployment region, defaulting to `us-west-2`.
8. WHEN the `dry-run` command is executed, THE Orchestrator SHALL output the plan in a human-readable format that includes per-account scenario selections, per-scenario resource name mappings, and the CloudFormation parameter overrides that would be used.

### Requirement 8: Idempotent Deployment

**User Story:** As a security engineer, I want re-running the orchestrator to be safe and produce the same result, so that I can recover from partial failures without creating duplicate resources.

#### Acceptance Criteria

1. WHEN the Orchestrator deploys to an account that already has a DEPLOYED scenario, THE Orchestrator SHALL detect the existing stack and skip re-creation for that scenario.
2. WHEN the Orchestrator deploys to an account that has a FAILED scenario, THE Orchestrator SHALL attempt to delete the failed stack and redeploy the scenario.
3. THE Orchestrator SHALL use the Deterministic_Seed to produce the same scenario selection and randomized names on every run for the same account, ensuring consistency across retries.
4. WHEN the Orchestrator detects that a deployed stack's parameters match the expected randomized names, THE Orchestrator SHALL report the scenario as up-to-date and take no action.
5. IF the Orchestrator detects a deployed stack with parameters that differ from the expected randomized names (indicating a seed or configuration change), THEN THE Orchestrator SHALL report the drift and require explicit confirmation before updating.

### Requirement 9: Error Handling and Partial Rollback

**User Story:** As a security engineer, I want the orchestrator to handle deployment failures gracefully and continue processing remaining accounts, so that a single account failure does not block the entire deployment.

#### Acceptance Criteria

1. IF a CloudFormation stack creation fails in a Member_Account, THEN THE Orchestrator SHALL record the Deployment_Status as FAILED, log the CloudFormation stack events describing the failure, and continue deploying remaining scenarios in the same account and remaining accounts.
2. IF the Orchestrator fails to assume the Deployment_Role in a Member_Account, THEN THE Orchestrator SHALL skip all scenarios for that account, log the error, and continue processing remaining accounts.
3. WHEN the Orchestrator completes a deployment run, THE Orchestrator SHALL display a summary showing the count of successful deployments, failed deployments, and skipped accounts.
4. THE Orchestrator SHALL support a `--retry-failed` flag on the `deploy` command that targets only accounts and scenarios with a FAILED Deployment_Status in the Deployment_Manifest.
5. IF a teardown operation fails to delete a CloudFormation stack, THEN THE Orchestrator SHALL log the error, retain the current Deployment_Status, and continue processing remaining scenarios and accounts.

### Requirement 10: Teardown Operations

**User Story:** As a security engineer, I want to cleanly remove all deception scenarios from specific accounts or all accounts, so that I can decommission the deception infrastructure when needed.

#### Acceptance Criteria

1. WHEN the `teardown` command is executed for a Member_Account, THE Orchestrator SHALL delete all deception CloudFormation stacks in that account by assuming the Deployment_Role and calling CloudFormation DeleteStack for each deployed scenario.
2. WHEN tearing down a scenario that includes S3 buckets, THE Orchestrator SHALL empty the bucket contents before deleting the CloudFormation stack to prevent deletion failures.
3. WHEN tearing down a scenario that includes ECR repositories, THE Orchestrator SHALL delete all images in the repository before deleting the CloudFormation stack.
4. WHEN all scenarios are successfully torn down from a Member_Account, THE Orchestrator SHALL update the Deployment_Manifest records for that account to Deployment_Status DELETED.
5. THE Orchestrator SHALL support tearing down a single scenario from an account using a `--scenario` flag combined with the `--account` flag.

### Requirement 11: Deployment Manifest Data Seeding

**User Story:** As a security engineer, I want the orchestrator to seed fake data into deployed scenario resources after stack creation, so that the deception resources contain realistic content that attracts attacker interaction.

#### Acceptance Criteria

1. WHEN a scenario stack is successfully created, THE Orchestrator SHALL execute the data seeding operations defined in the scenario's `fake-data/` directory using the assumed Deployment_Role credentials.
2. THE Orchestrator SHALL seed S3 buckets with fake data files (Terraform state files, SSH keys, compliance reports, pipeline artifacts) using the randomized bucket names.
3. THE Orchestrator SHALL seed DynamoDB tables with fake records (customer profiles, session records, enriched user profiles) using the randomized table names.
4. THE Orchestrator SHALL seed Secrets Manager secrets with fake credential JSON using the randomized secret names.
5. THE Orchestrator SHALL seed SSM parameters with fake configuration JSON using the randomized parameter paths.
6. THE Orchestrator SHALL seed SQS queues with fake message payloads using the randomized queue names.
7. THE Orchestrator SHALL seed CloudWatch log groups with fake log entries containing planted credentials using the randomized log group names.
8. IF data seeding fails for a scenario, THEN THE Orchestrator SHALL log the error but retain the Deployment_Status as DEPLOYED since the CloudFormation stack was created successfully.

### Requirement 12: Organization Account Discovery

**User Story:** As a security engineer, I want the orchestrator to automatically discover all member accounts in the AWS Organization, so that I do not need to manually maintain an account list.

#### Acceptance Criteria

1. WHEN the `--all` flag is used, THE Orchestrator SHALL call AWS Organizations ListAccounts to retrieve all active accounts in the organization.
2. THE Orchestrator SHALL exclude the Security_Account and the management account from the deployment target list when using the `--all` flag.
3. THE Orchestrator SHALL filter out suspended accounts from the target list.
4. THE Orchestrator SHALL accept a `--exclude-accounts` flag to exclude specific account IDs from the target list when using the `--all` flag.
5. IF the Orchestrator does not have permission to call AWS Organizations ListAccounts, THEN THE Orchestrator SHALL report the error and suggest using explicit account IDs with the `--account` or `--accounts` flags.

### Requirement 13: Deployment Logging and Audit Trail

**User Story:** As a security engineer, I want detailed deployment logs, so that I can audit what was deployed, when, and by whom.

#### Acceptance Criteria

1. THE Orchestrator SHALL log each deployment action (stack creation, data seeding, manifest update, teardown) with a timestamp, target account ID, scenario number, and outcome (success or failure with error details).
2. THE Orchestrator SHALL log the complete Resource_Map and Role_Map for each account during deployment for audit purposes.
3. THE Orchestrator SHALL write logs to both standard output and a log file in the current working directory with a filename that includes the run timestamp.
4. WHEN the `dry-run` command is executed, THE Orchestrator SHALL log the planned actions at the same detail level as an actual deployment, prefixed with `[DRY-RUN]`.

### Requirement 14: Cost Guardrails

**User Story:** As a security engineer, I want the orchestrator to enforce cost guardrails, so that deception deployments do not incur unexpected AWS charges.

#### Acceptance Criteria

1. THE Deployment_Manifest DynamoDB table SHALL use on-demand (PAY_PER_REQUEST) billing mode to avoid provisioned capacity costs.
2. THE Orchestrator SHALL NOT deploy more than 8 scenarios to any single Member_Account.
3. THE Orchestrator SHALL NOT deploy fewer than 4 scenarios (the core set) to any single Member_Account.
4. WHEN deploying scenario 4 (SSH Key to EC2 Bastion), THE Orchestrator SHALL verify that the EC2 instance is deployed in a stopped state and SHALL NOT start the instance.
5. THE Orchestrator SHALL tag all deployed CloudFormation stacks with a `DeceptionOrchestrator: true` tag and a `DeployedAt` tag containing the ISO 8601 deployment timestamp.
