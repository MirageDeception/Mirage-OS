# Naming Map — v1 (Original) vs v2 (New)

Use this to track what changed and revert if needed.

## CloudFormation Stack Names

| Component | v1 (Original — teammate managing) | v2 (New — separate) |
|-----------|------------------------------------|--------------------|
| CSC Prod brain | `deception-monitoring-architecture` | `deception-v2-monitoring-brain` |
| CSC Prod detection rules | (manual rules, no stack) | `deception-v2-detection-rules` |
| Dev account forwarding | `deception-forwarding-rule` | `deception-v2-forwarding` |

## AWS Resource Names

### CSC Prod (913511275171)

| Resource | v1 (Original) | v2 (New) |
|----------|---------------|----------|
| SNS Topic | `deception-monitoring-alerts` | `deception-v2-alerts` |
| Lambda Function | `deception-event-processor` | `deception-v2-event-processor` |
| Lambda Execution Role | `deception-lambda-execution-role` | `deception-v2-lambda-role` |
| EventBridge Invoke Role | `deception-eventbridge-invoke-lambda-role` | `deception-v2-invoke-lambda-role` |
| EventBus | `deception-global-event-bus` | `deception-v2-global-bus` |
| Detection Rules | `deception-detect-scenario-XX` | `deception-v2-detect-XX` |

### Dev Account (046574264211)

| Resource | v1 (Original) | v2 (New) |
|----------|---------------|----------|
| Forwarding Role | `deception-eventbridge-forwarding-role` | `deception-v2-forwarding-role` |
| STS Rule | (various manual rules) | `deception-v2-fwd-sts-roles` |
| Resource Rule | (various manual rules) | `deception-v2-fwd-resources` |

## CloudFormation Export Names

| v1 Export | v2 Export |
|-----------|-----------|
| `deception-monitoring-sns-topic-arn` | `deception-v2-sns-topic-arn` |
| `deception-monitoring-lambda-arn` | `deception-v2-lambda-arn` |
| `deception-monitoring-lambda-name` | `deception-v2-lambda-name` |
| `deception-monitoring-global-event-bus-arn` | `deception-v2-global-bus-arn` |
| `deception-monitoring-global-event-bus-name` | `deception-v2-global-bus-name` |
| `deception-monitoring-invoke-lambda-role-arn` | `deception-v2-invoke-lambda-role-arn` |
| `deception-forwarding-role-arn` | `deception-v2-forwarding-role-arn` |

## Revert Script

To delete all v2 resources and go back to v1 only, run `cleanup-v2.sh`.
