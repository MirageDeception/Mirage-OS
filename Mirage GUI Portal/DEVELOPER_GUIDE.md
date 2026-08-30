# Developer Documentation: Mirage Enterprise Portal

> **DISCLAIMER:** This is a vibe-coded project and might have errors. If you find some, please raise a pull request or send an email to jainarham7006@gmail.com or devanshunagpal3@gmail.com.

## Table of Contents
1. [Architecture Overview](#1-architecture-overview)
   - 1.1. [Core Tech Stack](#11-core-tech-stack)
   - 1.2. [The Hub & Spoke Model](#12-the-hub--spoke-model)
2. [Data Flow & State Management](#2-data-flow--state-management)
   - 2.1. [Flat-File Databases](#21-flat-file-databases)
   - 2.2. [EventBridge Rule Bin-Packing](#22-eventbridge-rule-bin-packing)
3. [Backend Operations](#3-backend-operations)
   - 3.1. [Terraform API Execution (`/api/deploy-spoke`)](#31-terraform-api-execution-apideploy-spoke)
   - 3.2. [GitHub Synchronization (`sync-scenarios.sh`)](#32-github-synchronization-sync-scenariossh)
4. [Frontend Architecture](#4-frontend-architecture)
   - 4.1. [UI State & Notifications](#41-ui-state--notifications)
   - 4.2. [Next.js App Router Structure](#42-nextjs-app-router-structure)
5. [Contributing & Extending](#5-contributing--extending)
   - 5.1. [Adding New Scenarios](#51-adding-new-scenarios)
   - 5.2. [Extending the Telemetry Mapper](#52-extending-the-telemetry-mapper)

---

## 1. Architecture Overview

### 1.1. Core Tech Stack
The Mirage GUI Portal is built on a modern JavaScript stack designed for extremely fast prototyping and execution:
- **Framework:** Next.js (App Router) / React 19.
- **Styling:** Vanilla CSS (`globals.css`) with standard CSS variables for theming.
- **Backend Execution:** Node.js API routes utilizing `child_process.exec` to run shell scripts.
- **Infrastructure as Code:** Terraform is invoked dynamically via shell scripts to provision AWS resources.
- **SDKs:** AWS SDK v3 (`@aws-sdk/client-eventbridge`, `@aws-sdk/client-iam`, etc.) used heavily in the backend API for rule automation.

### 1.2. The Hub & Spoke Model
Mirage is designed for Enterprise-scale AWS environments.
- **The Brain (Hub):** A central AWS account containing an EventBridge EventBus. All threat telemetry (CloudTrail events) is routed here.
- **The Decoys (Spokes):** Terraform provisions lightweight decoy resources (Honey Attack Paths) in these accounts. Local EventBridge rules in the Spoke accounts immediately capture malicious interactions with these specific resources and forward them cross-account to the Hub.

---

## 2. Data Flow & State Management

### 2.1. Flat-File Databases
To keep the portal lightweight and easy to self-host, Mirage intentionally avoids complex external databases (like PostgreSQL/MongoDB). It uses a local, self-healing flat-file database system located in the root directory (all ignored via `.gitignore`):
- `db_inventory.txt`: A line-by-line ledger tracking every decoy deployed. Each line contains: `[AccountID] | [ScenarioName] | [RuleName] | [DecoyResourceName] | [DecoyCategory]`.
- `db_rules.json`: A JSON ledger tracking the exact character footprint of every generated EventBridge rule.
- `db_history.json`: An array of audit logs tracking deployment success/failures.

*Self-Healing Mechanism:* The `lib/db.ts` module uses Node's `fs` promises to verify if these files exist on boot. If missing (e.g., a fresh clone), it automatically provisions empty templates.

### 2.2. EventBridge Rule Bin-Packing
Because AWS imposes strict character limits on EventBridge rule patterns (usually ~2048 chars), Mirage implements a complex "Bin-Packing" algorithm when generating telemetry rules.
1. When a scenario is deployed, the backend API parses the Terraform `outputs.json` to extract decoy names.
2. It constructs an AWS CloudTrail JSON filter for those decoys.
3. It checks `db_rules.json` to find an existing rule for that Spoke account.
4. If appending the new decoys keeps the rule under the character quota limit, it updates the existing AWS rule.
5. If the limit is breached, it seamlessly provisions a *new* rule in AWS and logs it in the database.
6. **Teardown:** When a scenario is deleted, the backend parses the monolithic rule, splices out *only* the deleted decoys, and patches the AWS rule.

---

## 3. Backend Operations

### 3.1. Terraform API Execution (`/api/deploy-spoke`)
Next.js API routes act as a bridge between the React frontend and the underlying OS shell.
- When you click "Deploy" in the UI, `src/app/catalog/page.tsx` sends a POST request to `/api/deploy-spoke`.
- The route dynamically builds environment variables (AWS Role ARNs, Account IDs) and spawns `src/scripts/deploy-spoke.sh` via `child_process`.
- The shell script navigates to the dynamically cloned Terraform template in `src/templates/mirage-os/...` and executes `terraform init && terraform apply -auto-approve`.
- The API waits for the exit code. Upon success, it fires the EventBridge rule generation logic using the AWS SDK, then writes to the flat-file databases.

### 3.2. GitHub Synchronization (`sync-scenarios.sh`)
The portal decouples its UI from the actual attack path definitions. 
- The `sync-scenarios.sh` script executes a hard reset against the remote `MirageDeception/Mirage-OS` GitHub repository.
- It pulls the latest Terraform scenarios into the ephemeral `src/templates/mirage-os` folder.
- **Developer Note:** If you are actively developing new Terraform scenarios locally inside the portal, you must change `SYNC_MODE="remote"` to `SYNC_MODE="local"` in the script. Otherwise, your uncommitted Terraform files will be forcefully wiped by the git reset!

---

## 4. Frontend Architecture

### 4.1. UI State & Notifications
- **Global State:** Managed heavily via React `useState` and `useEffect` hooks in `src/app/catalog/page.tsx`.
- **Notifications:** A custom, `localStorage`-backed notification system. Actions (like a successful deploy or a GitHub sync) trigger the `addNotification` helper, which writes to an in-memory array and persists it to the browser storage. A `useRef` based click-outside listener manages the dropdown UI panel.

### 4.2. Next.js App Router Structure
- `src/app/page.tsx` -> The core Dashboard layout.
- `src/app/catalog/page.tsx` -> The massive monolithic controller for the Deception Catalog, orchestrating deployments, rendering tabs, parsing rule diffs, and managing the activity feed.
- `src/components/` -> Smaller abstracted UI components (like the Toggle switches) that are imported into the main pages to prevent the page files from becoming overly bloated.

---

## 5. Contributing & Extending

### 5.1. Adding New Scenarios
To add a new attack path:
1. Create a new folder (e.g., `scenario-X`) in the upstream GitHub repository.
2. Write your `main.tf`, `variables.tf`, and `outputs.tf`.
3. **CRITICAL:** Your `outputs.tf` *must* contain a `decoy_resources` JSON array output block mapping the resource `.name` to the correct AWS Service category (e.g., `category = "s3"`). The portal's API strictly relies on this JSON block to automate the EventBridge telemetry routing.

### 5.2. Extending the Telemetry Mapper
If you write a scenario using an AWS service that the portal currently doesn't track (e.g., Redshift or RDS):
1. Open the backend API route that handles rule generation.
2. Locate the logic that maps the `category` string to specific AWS API Calls (e.g., mapping `s3` to `GetObject`, `ListBucket`, etc.).
3. Add your new service and its highly-sensitive CloudTrail API actions to the mapping array.
