# Cloud Deception — Executive One-Pager

**Project:** AWS Cloud Deception Infrastructure | **Team:** Cybersecurity Engineering | **Date:** June 2026

---

## The Problem

When an attacker compromises a cloud identity, our current detection tools (Wiz, GuardDuty, Security Hub) take **10–50+ hours** to generate a confirmed incident — because early reconnaissance looks identical to normal user activity and requires human confirmation loops.

## The Solution

Deploy realistic honeypot resources (fake secrets, credentials, databases, roles) across all 100+ AWS accounts that act as **silent tripwires**. No legitimate user or automation should ever touch these resources — so any interaction is an immediate, confirmed true positive.

## How It Works

```
Attacker enters account → Enumerates resources → Touches a decoy → ALERT in 8–12 seconds
                                                                    (zero false positives)
```

## Key Metrics

| Metric | Before | After |
|--------|--------|-------|
| Time to confirmed detection | 10–50+ hours | **8–12 seconds** |
| False positive rate | High (requires tuning) | **Zero** |
| Coverage | Varies by tool | **100+ accounts, 19 scenarios** |
| Monthly cost (entire org) | — | **~$150/month** |
| Maintenance required | Continuous tuning | **Zero-touch** (auto-deploys to new accounts) |

## What We Deploy (19 Scenarios)

Decoys cover the full attacker kill chain:

- **Credential theft** — Fake Stripe keys, DB passwords, API tokens in Secrets Manager, SSM, S3
- **Lateral movement** — Lure IAM roles, SSH keys, Lambda functions with pivot opportunities
- **Data exfiltration** — Fake customer PII tables, payment queues, container images
- **Infrastructure recon** — Fake encryption keys, SSO providers, CloudFormation outputs

Each decoy uses realistic production naming. Attackers cannot distinguish lures from real infrastructure.

## Why Existing Tools Miss This

| Tool | Strength | Blind Spot |
|------|----------|-----------|
| Wiz | Misconfigurations & posture | Can't detect an attacker using valid credentials normally |
| GuardDuty | Known attack signatures | Misses low-and-slow targeted enumeration |
| Security Hub | Compliance benchmarks | Not a real-time detection tool |

**Cloud Deception fills the gap** — it detects the reconnaissance phase before any real data is touched.

## POC Status: Complete ✓

- 4 scenarios tested in a dev account
- 100% detection rate, 8–12 second latency, zero false positives over 7 days
- Architecture validated: CloudTrail → EventBridge → Lambda → SNS/Torq

## Cost

| Component | Monthly |
|-----------|---------|
| Decoy resources (100 accounts × ~$1.50 avg) | ~$150 |
| Monitoring stack (EventBridge + Lambda + SNS) | ~$0 |
| **Total** | **~$150/month** |

## Next Steps

1. **Pilot** — Deploy core scenarios to 5–10 accounts, integrate Torq for automated response
2. **Full rollout** — StackSets deployment to all accounts with randomized resource names
3. **Operationalize** — Torq playbooks, scenario rotation, monthly health checks

## Bottom Line

For less than $150/month, we shift from detecting attackers **after exfiltration** to catching them **during reconnaissance** — with zero false positives, zero maintenance, and full organizational coverage.

---

*Contact: Cybersecurity Engineering Team | Classification: Internal*
