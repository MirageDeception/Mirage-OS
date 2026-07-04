# Scenario 11

Deception Scenario 11 - DynamoDB Lure: Customer Profiles + Active Sessions.
Two DynamoDB tables seeded with fake PII and JWT session tokens.
A single IAM role grants read-only access to both tables.
Every scan or query generates CloudTrail events for detection.
