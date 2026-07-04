# Implementation Plan: Deception Monitoring Stack

## Overview

Build a hybrid monitoring and alerting pipeline that detects attacker interactions with honeypot/decoy resources across 100+ AWS accounts. Implementation follows a bottom-up approach: Detection Lambda pure logic first (testable independently), then property-based tests, then CloudFormation templates (security account stack, member account StackSet), and finally integration wiring and deployment scripts.

All infrastructure is CloudFormation. The Detection Lambda is Python 3.12. Property-based tests use Hypothesis.

## Tasks

- [ ] 1. Implement Detection Lambda core logic
  - [ ] 1.1 Create the scenario registry module
    - Create `lambda/detection/scenario_registry.py` containing the `SCENARIO_REGISTRY` dictionary mapping all 19 scenarios to their description, resource names, expected monitored event names, and resource match type (exact, prefix, mixed)
    - Include the complete set of 22 lure role names and all resource-specific identifiers from the design
    - Ensure NO broad enumeration API calls are present in any scenario's event list (no ListBuckets, ListSecrets, DescribeParameters, ListTables, ListQueues, ListTopics, ListFunctions, ListRoles, ListAliases, ListKeys, DescribeLogGroups, ListStacks, ListSAMLProviders, ListExports, DescribeLogStreams, ListImages, DescribeRepositories, GetAuthorizationToken, ListGrants, ListRoleTags, GetResources)
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [ ] 1.2 Implement the resource matching and scenario lookup function
    - Create `lambda/detection/resource_matcher.py` with a function that extracts the resource identifier from a CloudTrail event (checking `requestParameters.roleName`, `requestParameters.functionName`, `requestParameters.tableName`, `requestParameters.bucketName`, `resources[].ARN`, and other service-specific fields)
    - Implement two-pass matching: extract resource identifier, then match against the scenario registry using exact, prefix, or mixed match types
    - Return the matched scenario number and description, or `None` if no match
    - _Requirements: 5.3, 9.1_

  - [ ] 1.3 Implement the severity classifier
    - Create `lambda/detection/severity.py` with a function that classifies events into exactly two tiers
    - CRITICAL: all resource-specific data access and interaction events (GetSecretValue, GetObject, Scan, Query, GetItem, ReceiveMessage, GetLogEvents, BatchGetImage, Decrypt, GetFunctionConfiguration20150331v2, DescribeStacks, DescribeKey, GetSAMLProvider, GetTopicAttributes, GetQueueAttributes, ListSubscriptionsByTopic, FilterLogEvents, GetDownloadUrlForLayer, StartInstances, AuthorizeSecurityGroupIngress, Publish, GetParameter, GetParametersByPath, DescribeTable)
    - HIGH: AssumeRole and AssumeRoleWithSAML targeting decoy roles, plus any unexpected event name for a known decoy resource
    - _Requirements: 5.4, 9.5_

  - [ ] 1.4 Implement the EventBridge event parser
    - Create `lambda/detection/event_parser.py` with a function that receives an EventBridge event envelope and extracts the six required fields: source account ID, event name, event time, source IP address, user identity ARN, and affected resource name from the `detail` field
    - Handle missing or malformed fields gracefully by logging errors
    - _Requirements: 5.1_

  - [ ] 1.5 Implement the CloudWatch Logs payload processor
    - In `lambda/detection/event_parser.py`, add a function that base64-decodes and gzip-decompresses a CloudWatch Logs subscription payload, parses the CloudTrail event records from the log data, and extracts the same six fields as the EventBridge parser
    - Handle decompression failures and malformed payloads by logging errors
    - _Requirements: 5.2_

  - [ ] 1.6 Implement the alert formatter
    - Create `lambda/detection/alert_formatter.py` with two functions: one that formats the enriched alert as a human-readable email string (with severity, scenario number/description, account ID, event name, event time UTC, source IP, user identity ARN, resource name, region), and one that formats it as a JSON object for Torq (with all the same fields plus the raw CloudTrail event)
    - _Requirements: 6.3, 6.4_

  - [ ] 1.7 Implement the Lambda handler entry point
    - Create `lambda/detection/handler.py` with the `lambda_handler` function that detects the event source (EventBridge vs CloudWatch Logs), delegates to the appropriate parser, runs scenario lookup and severity classification, formats the alert, and publishes to SNS
    - Implement error handling: log errors with original event payload to CloudWatch Logs and continue processing subsequent events on failure
    - Read the SNS topic ARN from the `SNS_TOPIC_ARN` environment variable
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

- [ ] 2. Checkpoint — Verify Detection Lambda logic
  - Ensure all Detection Lambda modules are syntactically correct and import cleanly. Ask the user if questions arise.

- [ ] 3. Write property-based tests for Detection Lambda logic
  - [ ]* 3.1 Write property test for event selector scope validation
    - **Property 1: Event Selector Scope Validation**
    - Generate random advanced event selector configurations (both scoped with specific ARN patterns and unscoped with wildcard-only selectors) using Hypothesis strategies; verify the validator rejects wildcard-only selectors and accepts scoped ones
    - **Validates: Requirements 2.5, 8.2**

  - [ ]* 3.2 Write property test for management event field extraction
    - **Property 2: Management Event Field Extraction**
    - Generate random valid CloudTrail management event JSON payloads via EventBridge envelope using Hypothesis; verify the parser extracts all six required fields (account ID, event name, event time, source IP, user identity ARN, resource name) and each is non-empty
    - **Validates: Requirements 5.1**

  - [ ]* 3.3 Write property test for CloudWatch Logs payload decompression and extraction
    - **Property 3: CloudWatch Logs Payload Decompression and Extraction**
    - Generate CloudTrail event records, compress them into CloudWatch Logs subscription format (base64 + gzip), and verify the processor round-trips correctly — producing the same six extracted fields as direct parsing of the uncompressed event
    - **Validates: Requirements 5.2**

  - [ ]* 3.4 Write property test for resource-to-scenario mapping
    - **Property 4: Resource-to-Scenario Mapping**
    - Sample from all registered decoy resource names in the scenario registry using Hypothesis; verify the mapping function returns the correct scenario number (1–19) and a non-empty description for each
    - **Validates: Requirements 5.3, 9.1**

  - [ ]* 3.5 Write property test for severity classification (two-tier)
    - **Property 5: Severity Classification (Two-Tier)**
    - Generate event names from both severity categories (CRITICAL list and HIGH list) using Hypothesis; verify CRITICAL events return CRITICAL, HIGH events return HIGH, and no event name maps to more than one severity level
    - **Validates: Requirements 5.4**

  - [ ]* 3.6 Write property test for alert formatting completeness
    - **Property 6: Alert Formatting Completeness**
    - Generate random enriched alert payloads using Hypothesis; verify both the email formatter and JSON formatter produce output containing all required fields (severity, scenario number, scenario description, account ID, event name, event time, source IP, user identity ARN, resource name, region) and the JSON output additionally includes the raw CloudTrail event
    - **Validates: Requirements 6.3, 6.4**

  - [ ]* 3.7 Write property test for unexpected event fallback classification
    - **Property 7: Unexpected Event Fallback Classification**
    - Generate (decoy resource, non-matching event name) pairs using Hypothesis where the event name is NOT in the scenario's expected event list; verify the severity is HIGH and the alert description indicates an unexpected interaction pattern
    - **Validates: Requirements 9.5**

- [ ] 4. Write unit tests for Detection Lambda
  - [ ]* 4.1 Write unit tests for scenario registry completeness and accuracy
    - Verify all 19 scenarios (1–19) are present in the registry
    - Verify each scenario's event list matches the specification exactly per Requirement 9.2
    - Verify no scenario contains any of the 21 excluded broad enumeration API calls
    - Verify scenario numbering and descriptions match Requirement 9.3
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

  - [ ]* 4.2 Write unit tests for error handling paths
    - Test malformed EventBridge event (missing `detail` field) — Lambda logs error and continues
    - Test malformed CloudWatch Logs payload (decompression failure) — Lambda logs error and continues
    - Test SNS publish failure — Lambda raises exception for retry
    - Test unknown resource (no scenario match) — Lambda logs warning, does NOT alert
    - _Requirements: 5.6_

- [ ] 5. Checkpoint — Verify all Lambda tests pass
  - Run all property-based tests and unit tests. Ensure all tests pass. Ask the user if questions arise.

- [ ] 6. Create the security account CloudFormation template
  - [ ] 6.1 Create the security account stack template with event bus and trail resources
    - Create `templates/monitoring-stack.yaml` with Parameters: SecurityAccountId, OrganizationId, TorqWebhookUrl, AlertEmailAddress
    - Define the Central Event Bus (`deception-central-bus`) with a resource policy allowing `events:PutEvents` from the organization using `aws:PrincipalOrgID` condition
    - Define the Central Bus detection rule that matches all events and invokes the Detection Lambda
    - Define the Data Event Org Trail as an organization trail with management events DISABLED and advanced event selectors scoped to decoy S3 buckets (infra-terraform-state-*, devops-deploy-keys-*, compliance-audit-reports-*, prod-data-sync-artifacts-*), DynamoDB tables (prod-customer-profiles, prod-active-sessions, prod-enriched-user-profiles), SQS queues (prod-payment-events.fifo, prod-payment-events-dlq.fifo), and CloudWatch Logs log group (/prod/payment-service/application)
    - Define the CloudWatch Logs log group for trail delivery and the IAM role for CloudTrail to write to it
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 10.1_

  - [ ] 6.2 Add the Detection Lambda and SNS resources to the security account template
    - Define the Detection Lambda function (Python 3.12, 256 MB memory, 30s timeout, reserved concurrency 10) with inline code or a reference to the packaged deployment artifact
    - Define the Lambda execution IAM role with permissions for CloudWatch Logs, SNS publish, and the Lambda basic execution policy
    - Define EventBridge and CloudWatch Logs invoke permissions for the Lambda
    - Define the CloudWatch Subscription Filter on the trail log group with the OR-pattern filter matching decoy resource identifiers, targeting the Detection Lambda
    - Define the Alert SNS Topic with an email subscription (parameterized address) and an HTTPS subscription (parameterized Torq webhook URL)
    - Set the SNS topic policy to allow the Detection Lambda to publish
    - _Requirements: 4.1, 4.2, 5.5, 6.1, 6.2, 8.3, 8.4, 10.1, 10.3, 10.4_

  - [ ]* 6.3 Write validation tests for the security account CloudFormation template
    - Verify the template parses as valid CloudFormation YAML
    - Verify all required parameters are present (SecurityAccountId, OrganizationId, TorqWebhookUrl, AlertEmailAddress)
    - Verify the Data Event Trail has management events disabled
    - Verify advanced event selectors enumerate specific ARN patterns with no wildcards
    - Verify Lambda reserved concurrency ≤ 10 and timeout ≤ 30s
    - Verify the EventBridge resource policy contains `aws:PrincipalOrgID` condition
    - Verify the EventBridge event pattern includes only monitored events (no enumeration calls)
    - _Requirements: 2.2, 2.3, 2.5, 3.2, 8.1, 8.2, 8.3, 8.4, 10.1_

- [ ] 7. Create the member account StackSet CloudFormation template
  - [ ] 7.1 Create the member account StackSet template
    - Create `templates/member-account-monitoring.yaml` with Parameters: CentralEventBusArn, SecurityAccountId
    - Define the EventBridge forwarding rule on the default event bus matching CloudTrail management events with the full event pattern from the design (matching on `detail.eventName` for all 26 monitored events, combined with `$or` conditions on `detail.requestParameters` for all decoy resource identifiers — role names, function names, table names, topic/SAML names, KMS alias, log group, ECR repo, CloudFormation stack)
    - Define the IAM role for cross-account EventBridge PutEvents with trust policy scoped to the EventBridge service and permission to put events on the Central Event Bus ARN
    - The rule SHALL NOT match any of the 21 excluded broad enumeration API calls
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 7.1, 7.2, 7.4, 10.2, 10.4_

  - [ ]* 7.2 Write validation tests for the member account StackSet template
    - Verify the template parses as valid CloudFormation YAML
    - Verify required parameters are present (CentralEventBusArn, SecurityAccountId)
    - Verify the EventBridge event pattern contains all 22 lure role names
    - Verify the event pattern contains all decoy resource identifiers (function names, table names, etc.)
    - Verify the event pattern's `eventName` list contains only the 26 monitored events and none of the 21 excluded enumeration calls
    - Verify the IAM role trust policy is scoped to the EventBridge service
    - _Requirements: 1.2, 1.3, 1.4, 7.4, 10.2_

- [ ] 8. Checkpoint — Verify all templates and tests
  - Ensure all CloudFormation templates are valid YAML. Ensure all tests pass. Ask the user if questions arise.

- [ ] 9. Create deployment scripts and wire everything together
  - [ ] 9.1 Create the event selector scope validator
    - Create `lambda/detection/selector_validator.py` with a function that validates advanced event selector configurations — rejecting wildcard-only selectors that match all resources of a type and accepting selectors that enumerate specific decoy resource ARN patterns
    - This function is used by Property 1 tests and can be called during deployment validation
    - _Requirements: 2.5, 8.2_

  - [ ] 9.2 Create the deployment script for the security account stack
    - Create `scripts/deploy-security-stack.sh` that deploys `templates/monitoring-stack.yaml` via `aws cloudformation deploy` with the required parameters
    - Include parameter validation and error handling
    - _Requirements: 10.1_

  - [ ] 9.3 Create the deployment script for the member account StackSet
    - Create `scripts/deploy-member-stackset.sh` that creates or updates the StackSet using `templates/member-account-monitoring.yaml` with service-managed permissions and automatic deployment to new accounts in the organization
    - Pass the CentralEventBusArn and SecurityAccountId as parameters
    - _Requirements: 7.1, 7.2, 7.3, 10.2_

  - [ ] 9.4 Create a project README with deployment instructions
    - Create `README.md` documenting the architecture, prerequisites, deployment order (security account stack first, then member account StackSet), parameter descriptions, cost expectations, and how to verify the deployment
    - _Requirements: 10.1, 10.2_

- [ ] 10. Final checkpoint — Ensure all tests pass
  - Run all property-based tests, unit tests, and template validation tests. Ensure all tests pass. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at each phase
- Property tests validate the 7 correctness properties from the design document using Hypothesis
- Unit tests validate specific examples, edge cases, and error handling paths
- The Detection Lambda logic is implemented as separate pure-function modules for testability before being wired into the handler
- CloudFormation templates are split: security account stack vs member account StackSet template
- All 19 scenarios and their event mappings come from the design's SCENARIO_REGISTRY
