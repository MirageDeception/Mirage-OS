# Requirements Document

## Introduction

This feature builds a near real-time monitoring and alerting pipeline for the AWS cloud deception project. The project deploys honeypot/decoy resources across 100+ AWS accounts in an AWS Organization. When attackers interact with these decoy resources, CloudTrail events are generated. This monitoring stack detects those events and delivers enriched alerts via Email and Torq webhook within seconds.

The architecture uses a single event ingestion path through EventBridge. Management events flow automatically from the existing Wiz organization trail to EventBridge. Data events are added by configuring scoped advanced event selectors on the same trail, which also delivers them to EventBridge. Both event types are matched by a forwarding rule in each member account and sent to a centralized Detection Lambda in the security account.

Total cost target: under $1/month across all 100+ accounts (excluding the existing org trail and Secrets Manager costs from the deception scenarios themselves).

### Detection Strategy

Detection is tuned for high-confidence, low-noise alerts. The monitoring stack tracks exactly two categories of CloudTrail events:

**Category 1 — AssumeRole on lure roles:** No legitimate user or automation should assume these decoy roles. Any `AssumeRole` or `AssumeRoleWithSAML` event targeting a lure role name is a true positive.

**Category 2 — Resource-specific API calls on exact lure resource ARNs:** Calls that require a specific resource identifier (ARN, name, or ID) and target a decoy resource directly. If someone calls `GetSecretValue` on a decoy secret or `GetObject` on a decoy S3 bucket, they found the lure and are actively investigating it.

**Excluded from monitoring (false positive reduction):** All broad enumeration calls that return every resource of a type without targeting a specific one are excluded. These are made routinely by legitimate users, automation, AWS Config, Security Hub, and SSO: `ListBuckets`, `ListSecrets`, `DescribeParameters`, `ListTables`, `ListQueues`, `ListTopics`, `ListFunctions`, `ListRoles`, `ListAliases`, `ListKeys`, `DescribeLogGroups`, `ListStacks`, `ListSAMLProviders`, `ListExports`, `DescribeLogStreams`, `ListImages`, `DescribeRepositories`, `GetAuthorizationToken`, `ListGrants`, `ListRoleTags`, `GetResources`.

**Monitored events (resource-specific):** `AssumeRole`, `AssumeRoleWithSAML`, `GetObject`, `GetSecretValue`, `GetParameter`, `GetParametersByPath`, `Scan`, `Query`, `GetItem`, `ReceiveMessage`, `BatchGetImage`, `GetDownloadUrlForLayer`, `StartInstances`, `AuthorizeSecurityGroupIngress`, `Decrypt`, `DescribeKey`, `DescribeStacks`, `DescribeTable`, `GetTopicAttributes`, `GetQueueAttributes`, `GetFunctionConfiguration20150331v2`, `GetSAMLProvider`, `GetLogEvents`, `FilterLogEvents`, `ListSubscriptionsByTopic`, `Publish`.

All events flow through a single EventBridge path. The existing Wiz organization trail already logs management events, which are automatically delivered to EventBridge. By adding scoped advanced event selectors to the same trail, data events for decoy resources are also logged and delivered to EventBridge. A single forwarding rule in each member account catches both management and data events and sends them to the central event bus.

**Severity model (two tiers only):**
- **CRITICAL** — All resource-specific data access and interaction events targeting decoy resources.
- **HIGH** — `AssumeRole` and `AssumeRoleWithSAML` targeting decoy roles, plus any unexpected event name for a known decoy resource.

The MEDIUM tier has been eliminated. Enumeration calls that previously occupied MEDIUM are no longer monitored at all, removing the need for a third severity level.

## Glossary

- **Wiz_Org_Trail**: The existing AWS CloudTrail organization trail deployed for Wiz integration that logs management events across all accounts. This trail is extended with Advanced_Event_Selectors to also log scoped data events for decoy resources.
- **EventBridge_Forwarding_Rule**: An Amazon EventBridge rule deployed in each member account that matches CloudTrail events (both management and data) involving decoy resources and forwards them to the Central_Event_Bus in the Security_Account.
- **Central_Event_Bus**: A custom Amazon EventBridge event bus in the Security_Account that receives forwarded deception events from all member accounts.
- **Detection_Lambda**: An AWS Lambda function in the Security_Account that processes incoming deception events, enriches them with scenario metadata, and publishes structured alerts.
- **Security_Account**: The designated AWS account that hosts the centralized detection pipeline (Central_Event_Bus, Detection_Lambda, Alert_SNS_Topic).
- **Member_Account**: Any AWS account in the organization (other than the Security_Account) where deception scenarios are deployed.
- **Alert_SNS_Topic**: An Amazon SNS topic in the Security_Account that distributes alerts to Email and Torq_Webhook subscribers.
- **Torq_Webhook**: An HTTPS endpoint provided by the Torq platform for receiving structured JSON alert payloads for automated response workflows.
- **Deception_Scenario**: One of the 19 defined honeypot resource configurations (S3 buckets, Secrets Manager secrets, SSM parameters, DynamoDB tables, SQS queues, SNS topics, KMS keys, Lambda functions, CloudWatch Logs, ECR repos, IAM roles, CloudFormation stacks, SAML providers, resource tags).
- **Decoy_Resource**: An individual AWS resource deployed as part of a Deception_Scenario (e.g., the S3 bucket `infra-terraform-state-<account-id>` or the IAM role `payment-secrets-readonly-role`).
- **Advanced_Event_Selector**: A CloudTrail feature that filters data events by resource type and resource ARN, enabling cost-effective logging of only specific resources.
- **StackSet**: An AWS CloudFormation StackSet used to deploy identical infrastructure (EventBridge_Forwarding_Rules) across all Member_Accounts from a central management account.
- **Management_Event**: A CloudTrail event generated by AWS control plane API calls (e.g., AssumeRole, DescribeKey, DescribeStacks). These flow to EventBridge automatically from the Wiz_Org_Trail.
- **Data_Event**: A CloudTrail event generated by AWS data plane API calls (e.g., S3 GetObject, DynamoDB Scan, SQS ReceiveMessage, CloudWatch Logs GetLogEvents). These require explicit trail configuration to log and, once logged by the Wiz_Org_Trail with scoped Advanced_Event_Selectors, are also delivered to EventBridge.

## Requirements

### Requirement 1: Management Event Forwarding via EventBridge

**User Story:** As a security engineer, I want management events from decoy resource interactions to be forwarded from each member account to a central event bus, so that I can detect attacker activity in near real-time without enabling a second management event trail.

#### Acceptance Criteria

1. WHEN a CloudTrail management event matches a Decoy_Resource name, THE EventBridge_Forwarding_Rule SHALL forward the event to the Central_Event_Bus in the Security_Account.
2. THE EventBridge_Forwarding_Rule SHALL match AssumeRole events where the `requestParameters.roleName` field contains any of the following lure role names: `infra-s3-data-readonly-role`, `payment-secrets-readonly-role`, `infra-config-readonly-role`, `devops-s3-deploy-role`, `prod-bastion-ecr-role`, `lambda-ops-readonly-role`, `compliance-audit-readonly-role`, `prod-compliance-data-access-role`, `prod-microservice-auth-role`, `prod-microservice-data-role`, `prod-microservice-admin-role`, `customer-data-readonly-role`, `session-store-readonly-role`, `payment-queue-readonly-role`, `alerts-readonly-role`, `log-analysis-readonly-role`, `kms-audit-readonly-role`, `sso-audit-readonly-role`, `resource-inventory-readonly-role`, `etl-ops-readonly-role`, `cfn-audit-readonly-role`, `infra-params-readonly-role`.
3. THE EventBridge_Forwarding_Rule SHALL match resource-specific API calls where the request parameters target any of the following Decoy_Resource identifiers: Lambda function names (`prod-data-sync-processor`, `prod-compliance-report-generator`, `prod-user-data-enrichment`), DynamoDB table names (`prod-customer-profiles`, `prod-active-sessions`, `prod-enriched-user-profiles`), SNS topic name (`prod-alerts-critical`), SAML provider name (`ProdOktaSSO`), KMS alias (`alias/prod-customer-data-encryption`), CloudWatch log group (`/prod/payment-service/application`), ECR repository (`prod-payment-service`), and CloudFormation stack name (`prod-core-infrastructure`).
4. THE EventBridge_Forwarding_Rule SHALL NOT match broad enumeration API calls including `ListBuckets`, `ListSecrets`, `DescribeParameters`, `ListTables`, `ListQueues`, `ListTopics`, `ListFunctions`, `ListRoles`, `ListAliases`, `ListKeys`, `DescribeLogGroups`, `ListStacks`, `ListSAMLProviders`, `ListExports`, `DescribeLogStreams`, `ListImages`, `DescribeRepositories`, `GetAuthorizationToken`, `ListGrants`, `ListRoleTags`, or `GetResources`.
5. THE EventBridge_Forwarding_Rule SHALL be deployed to each Member_Account via a StackSet.
6. THE EventBridge_Forwarding_Rule SHALL NOT require a second CloudTrail trail for management events.

### Requirement 2: Data Event Collection via Existing Organization Trail

**User Story:** As a security engineer, I want data events from decoy resources to be logged by adding scoped advanced event selectors to the existing Wiz organization trail, so that I can detect data-plane attacker interactions without creating a new trail and while keeping additional costs under $0.10/month.

#### Acceptance Criteria

1. THE Orchestrator/deployment process SHALL add Advanced_Event_Selectors to the existing Wiz_Org_Trail to log data events for decoy resources.
2. THE Advanced_Event_Selectors SHALL NOT modify the existing management event logging configuration of the Wiz_Org_Trail.
3. THE Advanced_Event_Selectors SHALL restrict data event logging to only the following Decoy_Resource ARN patterns: S3 objects in buckets matching `infra-terraform-state-*`, `devops-deploy-keys-*`, `compliance-audit-reports-*`, and `prod-data-sync-artifacts-*`; DynamoDB tables `prod-customer-profiles`, `prod-active-sessions`, and `prod-enriched-user-profiles`; SQS queues `prod-payment-events.fifo` and `prod-payment-events-dlq.fifo`; and CloudWatch Logs log group `/prod/payment-service/application`.
4. THE data events logged by the existing trail SHALL be delivered to the default EventBridge bus in each Member_Account, where the EventBridge_Forwarding_Rule matches and forwards them to the Central_Event_Bus.
5. IF the Advanced_Event_Selectors are configured with unscoped data event selectors (no specific ARN patterns), THEN THE deployment process SHALL reject the configuration and report an error describing the cost risk.

### Requirement 3: Central Event Bus Configuration

**User Story:** As a security engineer, I want a central event bus in the security account that accepts events from all member accounts, so that all deception alerts are processed in one place.

#### Acceptance Criteria

1. THE Central_Event_Bus SHALL accept events from all Member_Accounts in the AWS Organization.
2. THE Central_Event_Bus SHALL have a resource policy that permits `events:PutEvents` from the organization (using `aws:PrincipalOrgID` condition).
3. WHEN an event arrives on the Central_Event_Bus, THE Central_Event_Bus SHALL invoke the Detection_Lambda.

### Requirement 4: Detection Lambda — Event Processing and Enrichment

**User Story:** As a security engineer, I want the detection Lambda to process events from the central event bus, enrich them with scenario context, and produce structured alerts, so that I receive actionable intelligence about attacker activity.

#### Acceptance Criteria

1. WHEN the Detection_Lambda receives an event from the Central_Event_Bus, THE Detection_Lambda SHALL parse the CloudTrail event from the `detail` field and extract the source account ID, event name, event time, source IP address, user identity ARN, and the affected Decoy_Resource name.
2. THE Detection_Lambda SHALL map each Decoy_Resource to its corresponding Deception_Scenario number and scenario description.
3. THE Detection_Lambda SHALL classify each event with a severity level using exactly two tiers: CRITICAL for resource-specific data access and interaction events (`GetSecretValue`, `GetObject`, `Scan`, `Query`, `GetItem`, `ReceiveMessage`, `GetLogEvents`, `BatchGetImage`, `Decrypt`, `GetFunctionConfiguration20150331v2`, `DescribeStacks`, `DescribeKey`, `GetSAMLProvider`, `GetTopicAttributes`, `GetQueueAttributes`, `ListSubscriptionsByTopic`, `FilterLogEvents`, `GetDownloadUrlForLayer`, `StartInstances`, `AuthorizeSecurityGroupIngress`, `Publish`, `GetParameter`, `GetParametersByPath`, `DescribeTable`), and HIGH for role assumption events (`AssumeRole`, `AssumeRoleWithSAML`) targeting decoy roles plus any unexpected event name for a known Decoy_Resource.
4. THE Detection_Lambda SHALL publish the enriched alert to the Alert_SNS_Topic.
5. IF the Detection_Lambda fails to process an event, THEN THE Detection_Lambda SHALL log the error with the original event payload to CloudWatch Logs and continue processing subsequent events.

### Requirement 5: Alert Formatting and Distribution

**User Story:** As a security engineer, I want alerts delivered via email in a human-readable format and via Torq webhook in structured JSON, so that I can both manually triage and automate response workflows.

#### Acceptance Criteria

1. THE Alert_SNS_Topic SHALL have an email subscription that delivers formatted alert messages.
2. THE Alert_SNS_Topic SHALL have an HTTPS subscription pointing to the Torq_Webhook endpoint.
3. WHEN the Detection_Lambda publishes an alert, THE email message SHALL include: severity level, scenario number and description, source account ID, event name, event time (UTC), source IP address, user identity ARN, affected Decoy_Resource name, and the AWS region.
4. WHEN the Detection_Lambda publishes an alert, THE Torq_Webhook payload SHALL be a JSON object containing the fields: severity, scenario_number, scenario_description, account_id, event_name, event_time, source_ip, user_identity_arn, resource_name, region, and the raw CloudTrail event.

### Requirement 6: Cross-Account Deployment via StackSets

**User Story:** As a security engineer, I want the per-account monitoring components deployed consistently across all 100+ accounts via CloudFormation StackSets, so that new accounts automatically receive monitoring coverage.

#### Acceptance Criteria

1. THE StackSet SHALL deploy the EventBridge_Forwarding_Rule to all Member_Accounts in the organization.
2. THE StackSet SHALL deploy IAM roles required for EventBridge cross-account event forwarding.
3. WHEN a new Member_Account is added to the organization, THE StackSet SHALL automatically deploy the monitoring components to the new account.
4. THE StackSet template SHALL accept the Central_Event_Bus ARN and Security_Account ID as parameters.

### Requirement 7: Cost Guardrails

**User Story:** As a security engineer, I want hard cost guardrails in the architecture to prevent accidental cost explosions, so that the monitoring stack remains under $1/month total.

#### Acceptance Criteria

1. THE Advanced_Event_Selectors added to the existing Wiz_Org_Trail SHALL NOT modify the trail's existing management event configuration.
2. THE Advanced_Event_Selectors SHALL enumerate specific Decoy_Resource ARN patterns and SHALL NOT use wildcard-only selectors that match all resources of a type.
3. THE Detection_Lambda SHALL have a reserved concurrency limit to prevent runaway invocations.
4. THE Detection_Lambda SHALL have a timeout configured to prevent long-running executions.
5. THE Alert_SNS_Topic SHALL NOT have more than 10 subscriptions to limit notification costs.

### Requirement 8: Scenario-to-Event Mapping Registry

**User Story:** As a security engineer, I want a maintained mapping of all 19 deception scenarios to their monitored CloudTrail event signatures, so that the Detection_Lambda can accurately attribute events to scenarios.

#### Acceptance Criteria

1. THE Detection_Lambda SHALL contain a mapping registry that associates each of the 19 Deception_Scenarios with its Decoy_Resource names and expected monitored CloudTrail event names.
2. THE mapping registry SHALL cover the following monitored events per scenario: Scenario 1 (AssumeRole, GetObject), Scenario 2 (AssumeRole, GetSecretValue), Scenario 3 (AssumeRole, GetParameter, GetParametersByPath), Scenario 4 (AssumeRole, GetObject, AuthorizeSecurityGroupIngress, StartInstances), Scenario 5 (BatchGetImage, GetDownloadUrlForLayer), Scenario 6 (AssumeRole, GetFunctionConfiguration20150331v2, GetObject, GetSecretValue, GetParameter), Scenario 7 (AssumeRole ×2 roles, GetFunctionConfiguration20150331v2, GetObject, GetSecretValue, GetParameter), Scenario 8 (AssumeRole ×3 roles, GetParameter), Scenario 9 (AssumeRole, DescribeTable, Scan, Query, GetItem), Scenario 10 (AssumeRole, DescribeTable, Scan, Query), Scenario 11 (AssumeRole, GetQueueAttributes, ReceiveMessage), Scenario 12 (AssumeRole, GetTopicAttributes, ListSubscriptionsByTopic, Publish), Scenario 13 (AssumeRole, GetLogEvents, FilterLogEvents), Scenario 14 (AssumeRole, DescribeKey, Decrypt), Scenario 15 (AssumeRole, GetSAMLProvider, AssumeRoleWithSAML), Scenario 16 (AssumeRole), Scenario 17 (AssumeRole, GetFunctionConfiguration20150331v2, DescribeTable, Scan), Scenario 18 (AssumeRole, GetParameter, GetParametersByPath), and Scenario 19 (AssumeRole, DescribeStacks).
3. THE mapping registry SHALL use the following scenario numbering: Scenario 1 (Terraform State Lure, folder scenario-1), Scenario 2 (Payment Credentials, folder scenario-2), Scenario 3 (Infrastructure Vault, folder scenario-3), Scenario 4 (SSH Key → EC2 Bastion, folder scenario-4), Scenario 5 (ECR Container Image, folder scenario-5), Scenario 6 (Lambda Data Sync, folder scenario-6), Scenario 7 (Lambda Role Chaining, folder scenario-7), Scenario 8 (Role Chain Loop, folder scenario-9), Scenario 9 (Customer Profiles, folder scenario-11), Scenario 10 (Active Sessions, folder scenario-12), Scenario 11 (Payment Events DLQ, folder scenario-13), Scenario 12 (Critical Alerts, folder scenario-14), Scenario 13 (Leaked Logs, folder scenario-15), Scenario 14 (Encryption Key, folder scenario-16), Scenario 15 (Fake SSO, folder scenario-17), Scenario 16 (Tag Breadcrumbs, folder scenario-18), Scenario 17 (Enriched User PII, folder scenario-19), Scenario 18 (SSM Chain, folder scenario-20), and Scenario 19 (Stack Outputs, folder scenario-21).
4. THE mapping registry SHALL NOT include any broad enumeration API calls (ListBuckets, ListSecrets, DescribeParameters, ListTables, ListQueues, ListTopics, ListFunctions, ListRoles, ListAliases, ListKeys, DescribeLogGroups, ListStacks, ListSAMLProviders, ListExports, DescribeLogStreams, ListImages, DescribeRepositories, GetAuthorizationToken, ListGrants, ListRoleTags, GetResources).
5. IF a CloudTrail event matches a Decoy_Resource but the event name is not in the mapping registry for that scenario, THEN THE Detection_Lambda SHALL classify the event as severity HIGH with a description indicating an unexpected interaction pattern.

### Requirement 9: Infrastructure as Code

**User Story:** As a security engineer, I want all monitoring stack components defined as CloudFormation templates, so that the entire stack is version-controlled, repeatable, and auditable.

#### Acceptance Criteria

1. THE security account monitoring stack (Central_Event_Bus, Detection_Lambda, Alert_SNS_Topic) SHALL be defined in a CloudFormation template.
2. THE per-account monitoring components (EventBridge_Forwarding_Rule, cross-account IAM role) SHALL be defined in a separate CloudFormation template suitable for StackSet deployment.
3. THE Detection_Lambda source code SHALL be included inline in the CloudFormation template or packaged as a deployment artifact referenced by the template.
4. THE CloudFormation templates SHALL accept parameterized values for the Security_Account ID, Central_Event_Bus ARN, Torq_Webhook URL, and alert email address.
5. THE deployment process SHALL include a script or CloudFormation custom resource to configure the Advanced_Event_Selectors on the existing Wiz_Org_Trail for scoped data event logging.
