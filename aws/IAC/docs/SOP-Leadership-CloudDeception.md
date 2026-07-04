# Cloud Deception — Standard Operating Procedure (Leadership Overview)

**Owner:** Cyber Security Center (CSC) — Red Team & Detection Engineering
**Classification:** Confidential — FICO Internal
**Version:** 1.0 | May 2026

---

## What Is This?

Fake AWS resources (secrets, databases, roles, buckets) deployed across FICO cloud accounts that look like real production infrastructure. No legitimate user or system should ever interact with them. If someone does - it's an attacker.

---

## How It Works

| Step | What Happens | Time |
|------|-------------|------|
| 1 | Attacker compromises a FICO cloud account (credentials, insider, lateral movement) | — |
| 2 | Attacker enumerates the account and discovers decoy resources during reconnaissance | Minutes |
| 3 | Attacker interacts with a decoy (reads a fake secret, assumes a lure role, scans a fake table) | — |
| 4 | Alert fires immediately to SOC + Torq (automated response) | **5-15 seconds** |
| 5 | SOC initiates containment — no owner confirmation needed (zero false positives) | Immediate |

---

## What Makes This Different

| Traditional Detection | Cloud Deception |
|----------------------|-----------------|
| Alerts after exfiltration or abuse | Alerts during reconnaissance (before damage) |
| Requires severity triage and owner confirmation | Every alert is a true positive — act immediately |
| 10-50+ hours to incident creation | 5-15 seconds to alert |
| High false positive rate, alert fatigue | Zero false positives by design |

---

## Scope

- **Coverage:** 100+ AWS accounts across the organization
- **Scenarios:** 19 deception scenarios covering IAM, S3, Secrets Manager, SSM, DynamoDB, Lambda, SQS, SNS, KMS, ECR, CloudFormation, SAML, CloudWatch Logs
- **Deployment:** Automated via CloudFormation StackSets (zero-touch for new accounts)
- **Cost:** ~$0.06/month monitoring + ~$1.25-$3.70/account for decoy resources

---

## Response Procedure (When an Alert Fires)

1. **Alert received** — SOC and Torq webhook receive enriched alert (account, user identity, IP, resource, scenario)
2. **Immediate containment** — Revoke active sessions for the compromised identity (no owner confirmation required)
3. **Investigate** — Determine initial access vector using the identity ARN and source IP from the alert
4. **Scope** — Check if the same identity accessed real resources (CloudTrail query on the user ARN)
5. **Remediate** — Rotate credentials, patch access vector, notify affected teams
6. **Report** — Document as a security incident per standard IR process

**Key point:** Deception alerts bypass the normal "contact account owner to confirm" step. The resources are fake — any interaction is malicious by definition.

---

## Operational Assurance

- **No impact to production** — Decoy resources are isolated, contain only fake data, and have no connections to real systems
- **No user disruption** — Legitimate users and automation never interact with these resources
- **No additional headcount** — Fully automated detection and alerting; integrates with existing SOC workflow
- **Minimal cost** — Under $150/month for the entire organization (100+ accounts, tiered deployment)
- **Maintained by CSC** — Red Team and Detection Engineering own deployment, monitoring, and scenario updates



---

## Escalation Path

| Severity | Trigger | Action |
|----------|---------|--------|
| **CRITICAL** | Attacker read data from a decoy resource (secret, database, S3 object) | Immediate containment + P1 incident |
| **HIGH** | Attacker assumed a decoy IAM role (entry point confirmed) | Immediate containment + P2 incident |

---

## Questions?

Contact: CSC — Red Team & Detection Engineering
