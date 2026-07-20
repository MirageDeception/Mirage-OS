# Mirage-OS: Cloud Deception Infrastructure

Mirage-OS is a cross-account AWS cloud deception platform. It enables Security Operations Centers (SOCs) to proactively deploy high-fidelity honeypots, lures, and decoys (like fake S3 buckets with terraform state files, honey IAM roles, and exposed secrets) across multiple AWS accounts.

## Architecture

Mirage uses a **Hub and Spoke** architecture:
- **Hub Account**: Hosts the central EventBridge bus, the `mirage-brain` evaluation Lambda, and the SNS alerting topic.
- **Spoke Accounts**: Host the actual decoy resources and forward any CloudTrail events matching those decoys to the Hub.

## Installation

```bash
git clone https://github.com/mirage-security/mirage.git
cd mirage/Mirage-cli
make build
sudo mv build/mirage /usr/local/bin/mirage
```

## Quick Start

1. **Bootstrap Configuration**
   ```bash
   mirage init
   ```
   Follow the interactive prompts to define your Hub and Spoke account IDs.

2. **Deploy Cross-Account Roles**
   From the hub account profile:
   ```bash
   mirage roles deploy --all-spokes
   ```

3. **Deploy the Detection Pipeline**
   From the hub account profile:
   ```bash
   mirage monitor deploy
   ```
   Then, from each spoke account profile:
   ```bash
   mirage monitor forwarding
   ```

4. **Deploy Scenarios**
   From a spoke account profile:
   ```bash
   mirage scenario list
   mirage scenario deploy --all
   ```

5. **Verify the Deployment**
   ```bash
   mirage verify
   ```

## Security & Privacy
- All credentials are handled temporarily via `sts:AssumeRole`.
- Configuration and SQLite catalogues are created with `0600` permissions.
- No secrets are logged.
