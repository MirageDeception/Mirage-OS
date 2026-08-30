# Project Mirage | Enterprise Cloud Deception Platform

Welcome to **Project Mirage**, an open-source enterprise cloud security solution that uses strategic deception to neutralize threats. 

Unlike traditional security tools (like EDR or SIEM) that rely on analyzing past behavior to generate alerts, MIRAGE deploys a high-fidelity matrix of decoy assets and bait credentials directly into your environment. It misdirects attackers into isolated traps, triggering immediate, zero-false-positive alerts before core data can be breached.

## Table of Contents
1. [Prerequisites & Getting Started](#prerequisites--getting-started)
   - [System Prerequisites](#system-prerequisites)
   - [AWS Prerequisites](#aws-prerequisites)
   - [Installation](#installation)
   - [Launching the Portal](#launching-the-portal)
2. [What is Project Mirage?](#what-is-project-mirage)
3. [The Problem Statement](#the-problem-statement)
4. [How Mirage Solves It (Advantages)](#how-mirage-solves-it-advantages)
5. [Architecture](#architecture)
6. [Components of the Project](#components-of-the-project)

---

## Prerequisites & Getting Started

### System Prerequisites
To run the Mirage GUI Portal locally, your system must have the following dependencies installed:
- **Node.js** (v18 or higher recommended)
- **npm** (Node Package Manager)
- **Terraform** (v1.0.0 or higher) - *Required for the backend scripts to provision AWS infrastructure.*
- **Git** - *For cloning and syncing catalog scenarios.*
- **AWS CLI** - *Optional but recommended for verifying AWS credentials locally.*

> **Note:** The repository does **not** automatically install these dependencies upon cloning. You must manually install system tools (Terraform/Node.js) and run `npm install` for the project packages.

### AWS Prerequisites
For Mirage to function correctly, your AWS environments need:
- **AWS Credentials:** The environment running the portal must have valid AWS credentials configured (e.g., via `~/.aws/credentials` or exported environment variables) that allow it to assume the target deployment roles.
- **Hub Account (Brain):** An AWS account designated to act as the centralized monitoring hub.
- **Spoke Accounts:** One or more AWS accounts where the decoy infrastructure will be deployed.
- **Cross-Account Trust:** The IAM Deployment Roles used by Mirage in the Spoke and Hub accounts must have trust policies allowing the portal's execution environment to assume them.

### Installation
Clone the repository, switch to the GUI branch (if applicable), and manually install the required Node.js dependencies:

```bash
git clone https://github.com/MirageDeception/Mirage-OS.git
cd Mirage-OS
git checkout Mirage_GUI # Switch to the GUI branch
npm install
```

### Launching the Portal
Once dependencies are installed, start the local development server:

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to access the portal.

---

## What is Project Mirage?
**Project Mirage** is an automated, scalable enterprise deception platform designed to seamlessly integrate Honey Attack Paths (decoy infrastructure) across your AWS Spoke accounts. By deploying highly believable but completely fake infrastructure—like exposed IAM keys, vulnerable S3 buckets, and fake Secrets—Mirage lures bad actors into interacting with traps.

## The Problem Statement
As enterprise cloud environments expand rapidly across hundreds of accounts, security teams face several critical challenges:
1. **Alert Fatigue:** Traditional security tools generate massive volumes of alerts based on heuristic patterns, leading to alert fatigue and delayed incident response.
2. **Post-Breach Discovery:** Many modern breaches (especially credential compromise) are discovered weeks or months after the initial intrusion because legitimate credentials are used for lateral movement, blending in with regular traffic.
3. **Complex Telemetry:** Centralizing and making sense of API logs (like AWS CloudTrail) across hundreds of isolated Spoke accounts is expensive, noisy, and difficult to manage at scale.

## How Mirage Solves It (Advantages)
Mirage is built on the philosophy of **Active Defense**:
- **Zero False Positives:** Because decoy infrastructure has no legitimate business use, *any* interaction with it is inherently malicious. When an alert fires, you know it is a real threat.
- **Early Detection of Lateral Movement:** Attackers looking to escalate privileges or move laterally will inevitably scan for and stumble upon our distributed traps.
- **Automated Routing & Scale:** Mirage doesn't just deploy infrastructure; it automates the complex telemetry routing. It dynamically generates EventBridge rules that filter out the noise, ensuring only high-fidelity alerts are sent to your centralized Hub account.
- **Cost-Effective Logging:** By filtering events at the Spoke level (Tier 1) and Hub level (Tier 2), you avoid paying to ingest billions of harmless CloudTrail logs into your SIEM.

## Architecture
Mirage relies on a highly efficient **dual-tier filtering architecture**:

1. **The Spoke Account (Tier 1):** 
   - Decoy infrastructure (S3, IAM, Lambda, DynamoDB, etc.) is deployed here. 
   - A dynamic AWS EventBridge rule is generated locally to filter CloudTrail events. **Only** API calls interacting directly with the decoy resources are forwarded.
2. **The Hub/Brain Account (Tier 2):** 
   - A Global EventBus (`Mirage-Hub-Bus`) receives the filtered telemetry from all Spokes.
   - An Event Processor (AWS Lambda) listens to the bus, parses the events, maps them against your active decoy inventory, and formats them.
   - An Alert Dispatcher (Amazon SNS) instantly pushes the processed alerts to your configured endpoints (Slack, PagerDuty, etc.).

## Components of the Project
The MIRAGE ecosystem is modular and continuously expanding:
- **The GUI Portal (`Mirage_GUI` Branch):** A Next.js web application that serves as your command center for deploying the Brain, browsing the Deception Catalog, and managing active EventBridge rules.
- **Deception Catalog (`/scenarios`):** A curated, open-source collection of Terraform templates representing different deception attack scenarios and playbooks (e.g., Credential Theft, S3 Ransomware Bait, Lateral Movement).
- **Core Infrastructure Scripts:** Backend bash scripts that orchestrate Terraform and the AWS CLI to safely deploy both the Hub Brain and the Spoke decoys.
