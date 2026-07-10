# Mirage CLI — Build Tasks & Checklist

> Sequential build plan for Gemini. Each phase produces a working, testable
> binary. Complete phases in order — later phases depend on earlier ones.
>
> **Binary:** `mirage` | **Language:** Go 1.22+ | **Framework:** Cobra
> **IaC:** Terraform | **Catalogue:** SQLite (local) / DynamoDB (team)

---

## Phase 0: Project Scaffold & Core Packages

**Goal:** Compilable binary with root command, global flags, and foundational packages.

### Tasks

- [ ] **0.1** Initialize Go module: `go mod init github.com/org/mirage`
- [ ] **0.2** Create project layout:
  ```
  cmd/mirage/main.go
  internal/cmd/root.go
  internal/config/schema.go
  internal/config/loader.go
  internal/awsctx/identity.go
  internal/awsctx/role.go
  internal/awsctx/guard.go
  ```
- [ ] **0.3** Implement `root.go`: Cobra root command with global flags
  - `--region` (default: `us-west-2`, all regions supported)
  - `--profile` (AWS named profile)
  - `--yes / -y` (skip confirmations)
  - `--dry-run` (plan only)
  - `--json` (machine output)
  - `--verbose` (debug logging)
- [ ] **0.4** Implement `config/schema.go`: Full config struct matching
  `~/.mirage/config.yaml` schema (accounts, naming, catalogue, templates, alerts)
- [ ] **0.5** Implement `config/loader.go`: Read/write/validate `~/.mirage/config.yaml`
  - Create `~/.mirage/` directory if missing
  - YAML marshal/unmarshal with schema version check
  - Validate required fields (hub, spokes, naming.prefix)
- [ ] **0.6** Implement `awsctx/identity.go`: Call `sts:GetCallerIdentity`
  - Return: account_id, arn, principal
  - Handle: no creds, expired token, network error
- [ ] **0.7** Implement `awsctx/role.go`: Classify account as hub/spoke/unknown
  - Compare STS account vs config.accounts.hub / config.accounts.spokes
  - Return enum: `Hub | Spoke | Unknown`
- [ ] **0.8** Implement `awsctx/guard.go`: Middleware that refuses wrong-role
  - `Guard(requiredRole)` → returns error with profile switch hint if mismatch
  - Used as `PreRunE` in Cobra commands
- [ ] **0.9** Add `Makefile`: `build`, `test`, `lint`, `clean` targets
- [ ] **0.10** Verify: `go build ./cmd/mirage && ./mirage --help` works

### Acceptance
- Binary compiles and prints help
- Config loads/saves correctly
- STS identity resolution works with real AWS creds
- Guard correctly refuses when account doesn't match config

---

## Phase 1: Init Command (Bootstrap Wizard)

**Goal:** `mirage init` walks the user through setup and writes config.

### Tasks

- [ ] **1.1** Create `internal/cmd/init.go`: Cobra subcommand `init`
- [ ] **1.2** Implement welcome banner + cloud provider selection prompt
  - For now: only AWS supported (others print "coming soon")
- [ ] **1.3** Implement auth flow:
  - Call `awsctx.GetIdentity()` → display account + principal
  - If fails → guide user to configure creds
- [ ] **1.4** Implement org detection:
  - Try `organizations:DescribeOrganization`
  - If succeeds → org mode (list accounts available)
  - If fails (AccessDenied or no org) → standalone hub mode
- [ ] **1.5** Implement spoke enrollment prompts:
  - Single spoke / multi spoke (comma-separated)
  - Validate format (12-digit account IDs)
  - Assign aliases (user-provided or auto: spoke-1, spoke-2...)
- [ ] **1.6** Implement naming convention prompts:
  - Ask for prefix (default: "corp")
  - Show pattern preview: "corp-terraform-state-bucket"
  - Store in config.naming.prefix + default patterns
- [ ] **1.7** Implement catalogue backend selection:
  - SQLite (local, default) or DynamoDB (team)
  - If DynamoDB → record table name + region in config
- [ ] **1.8** Implement alert email collection:
  - Repeatable prompt or `--email` flag
- [ ] **1.9** Implement role deployment prompt:
  - "Deploy roles now? (Y/N)"
  - If Y → print "run `mirage roles deploy --all-spokes` next"
  - If N → note in config: roles_deployed = false
- [ ] **1.10** Write config to `~/.mirage/config.yaml`
- [ ] **1.11** Non-interactive mode: all values via flags
  - `--hub`, `--spoke` (repeatable), `--email` (repeatable),
    `--prefix`, `--catalogue`, `--org`/`--no-org`
- [ ] **1.12** Add `mirage config show` and `mirage config set <key> <value>`

### Acceptance
- `mirage init` walks through prompts and writes valid config
- `mirage init --hub X --spoke Y --email Z` works non-interactively
- `mirage config show` prints the saved config
- Config file validates on subsequent load

---

## Phase 2: Roles Management

**Goal:** `mirage roles` deploys/imports/validates cross-account IAM roles.

### Tasks

- [ ] **2.1** Create `internal/cmd/roles.go`: Cobra subcommand group `roles`
- [ ] **2.2** Create `internal/roles/` package structure:
  ```
  internal/roles/deploy.go
  internal/roles/import.go
  internal/roles/destroy.go
  internal/roles/status.go
  internal/roles/template.go
  ```
- [ ] **2.3** Create Terraform templates for roles:
  ```
  templates/roles/spoke-deployment-role/main.tf
  templates/roles/spoke-deployment-role/variables.tf
  templates/roles/spoke-deployment-role/outputs.tf
  templates/roles/spoke-forwarding-role/main.tf
  templates/roles/spoke-forwarding-role/variables.tf
  templates/roles/spoke-forwarding-role/outputs.tf
  ```
- [ ] **2.4** Implement `roles deploy`:
  - Guard: must be hub account
  - For each spoke in config:
    - Assume or use profile to reach spoke
    - terraform init/plan/apply for deployment-role + forwarding-role
    - Trust policy: hub account + ExternalId
    - Permissions: all deception resource types, no region restriction
    - Permission boundary: prevent IAM escalation
  - Update hub EventBus policy (allow PutEvents from forwarding roles)
  - Write role ARNs to config
- [ ] **2.5** Implement `roles import`:
  - Takes: `<spoke-alias> --role-arn <arn> [--forwarding-role-arn <arn>]`
  - Validate: attempt `sts:AssumeRole` on provided ARN from hub
  - Check: attached policies cover required actions (list + compare)
  - If insufficient: print required policy JSON for manual attachment
  - Write ARN to config (no infra deployed)
- [ ] **2.6** Implement `roles status`:
  - For each spoke with role ARN in config:
    - Attempt AssumeRole → success/fail
    - Check policy attachments
    - Check last-used date (stale if >90 days)
  - Print matrix: spoke | role_arn | assumable | policy_ok | last_used
- [ ] **2.7** Implement `roles destroy`:
  - Guard: must be hub account
  - Double-confirm ("type spoke alias to confirm")
  - terraform destroy for role resources in target spoke
  - Revoke hub bus policy entry for this spoke
  - Remove role ARNs from config
- [ ] **2.8** Implement `roles export-template`:
  - Generate standalone .tf file (or .yaml CFN) for spoke admin
  - Include: trust policy, permissions, boundary, outputs
  - Flags: `--spoke <alias>`, `--format terraform|cloudformation`
  - Print instructions: "Give this to spoke admin → they apply → you import"
- [ ] **2.9** Handle flags: `--spoke <alias>`, `--all-spokes`, `--hub`,
  `--dry-run`, `--export-template`

### Acceptance
- `mirage roles deploy --all-spokes` creates roles in spoke accounts
- `mirage roles import dev --role-arn ...` validates and writes to config
- `mirage roles status` shows health matrix
- `mirage roles destroy --spoke dev` removes roles with double-confirm
- Exported template is valid Terraform that applies independently

---

## Phase 3: Naming Engine & Template System

**Goal:** Config-driven resource naming + template fetch/cache/verify.

### Tasks

- [ ] **3.1** Create `internal/naming/` package:
  ```
  internal/naming/resolver.go
  internal/naming/variables.go
  internal/naming/tfvars.go
  ```
- [ ] **3.2** Implement `resolver.go`: Pattern interpolation engine
  - Input: scenario number, resource type, config naming section
  - Resolution order: CLI flag > config override > config pattern > placeholder
  - Variables: `{prefix}`, `{scenario_slug}`, `{suffix}`, `{key}`,
    `{region}`, `{account_id}`, `{spoke_alias}`
  - Validate: no two scenarios produce the same resource name (collision check)
- [ ] **3.3** Implement `tfvars.go`: Generate `.tfvars` file from resolved names
  - Input: scenario manifest (lists required TF variables) + resolved names
  - Output: `scenario-N.tfvars` file with one `key = "value"` per line
  - Include: account_id, region, all resource names
- [ ] **3.4** Create `internal/templates/` package:
  ```
  internal/templates/fetcher.go
  internal/templates/cache.go
  internal/templates/integrity.go
  ```
- [ ] **3.5** Implement `fetcher.go`: Pull templates from configured source
  - Support: GitHub raw URL, local filesystem path, S3 (future)
  - Download scenario-N/ directory contents (main.tf, variables.tf, etc.)
- [ ] **3.6** Implement `cache.go`: Local template cache management
  - Cache location: `~/.mirage/templates/scenario-N/`
  - Check: is cached version current? (compare hash)
  - Commands: force-refresh, clear cache
- [ ] **3.7** Implement `integrity.go`: SHA256 verification
  - Fetch `manifest.json` from template source (contains per-scenario hashes)
  - Before apply: hash local template files, compare to manifest
  - Mismatch → warn "template modified locally or upstream changed"
- [ ] **3.8** Create `internal/discovery/` package:
  ```
  internal/discovery/scanner.go
  internal/discovery/manifest.go
  internal/discovery/filter.go
  ```
- [ ] **3.9** Implement `scanner.go`: Walk template source, parse scenario.yaml
  - List all available scenarios from template source
  - Parse each scenario.yaml → Scenario struct
  - Skip folders with no main.tf (empty placeholders)
- [ ] **3.10** Implement `filter.go`: Filter scenarios by service/category
  - `--service s3` → only S3-based scenarios
  - `--category credential-theft` → only credential scenarios
- [ ] **3.11** Define `scenario.yaml` schema (Go struct):
  - number, name, slug, version, category, service
  - resources[] (type, tf_variable, purpose)
  - seed[] (kind, source, destination_key)
  - detection (events, severity)
  - terraform (required_variables, outputs)

### Acceptance
- Naming resolver produces correct names from config patterns
- Overrides take precedence over patterns
- Collision detection catches duplicate names across scenarios
- Generated .tfvars files are valid Terraform input
- Templates fetch from GitHub, cache locally, verify integrity
- Discovery lists all scenarios with correct metadata

---

## Phase 4: Catalogue (Resource Registry)

**Goal:** SQLite/DynamoDB catalogue tracks all deployed resources.

### Tasks

- [ ] **4.1** Create `internal/catalogue/` package:
  ```
  internal/catalogue/store.go       (interface)
  internal/catalogue/sqlite.go
  internal/catalogue/dynamodb.go
  internal/catalogue/operations.go
  internal/catalogue/audit.go
  ```
- [ ] **4.2** Define `Store` interface:
  ```go
  type Store interface {
    Register(resource Resource) error
    Deregister(id string) error
    ListBySpoke(alias string) ([]Resource, error)
    ListByScenario(num int) ([]Resource, error)
    GetResource(account, scenario, resType string) (*Resource, error)
    UpdateVerified(id string, timestamp time.Time) error
    Sync(liveState []Resource) (SyncReport, error)
    LogOperation(op Operation) error
    Export(format string) ([]byte, error)
  }
  ```
- [ ] **4.3** Implement `sqlite.go`:
  - Create DB at `~/.mirage/catalogue.db`
  - Tables: `resources`, `operations_log`, `spokes`
  - Indices on spoke_alias, scenario_num, status
- [ ] **4.4** Implement `dynamodb.go`:
  - Tables: `mirage-resource-catalogue`, `mirage-operations-log`
  - PK/SK design per data model doc
  - Create tables if not exists (on first use)
- [ ] **4.5** Implement `operations.go`:
  - `Register`: insert resource entry after terraform apply (capture ARN from output)
  - `Deregister`: mark destroyed_at + status=destroyed (retain history)
  - `Sync`: compare catalogue entries vs terraform state vs live AWS describe calls
    - Flag: orphaned (in catalogue, not in AWS), phantom (in AWS, not in catalogue)
- [ ] **4.6** Implement `audit.go`:
  - Every mutating command logs: timestamp, operator (STS principal),
    command string, account, spoke, scenario, action, result, details
  - Never logs secrets or credentials
- [ ] **4.7** Create `internal/cmd/catalogue.go`:
  - `mirage catalogue show [--spoke <alias>] [--json]`
  - `mirage catalogue sync [--spoke <alias>]`
  - `mirage catalogue export [--format json|csv]`

### Acceptance
- SQLite DB created on first use; schema migrations work
- Register/deregister correctly tracks resource lifecycle
- Sync detects orphans and phantoms with clear report
- Operations log captures all mutations with operator identity
- `catalogue show` displays readable table; `--json` outputs valid JSON
- `catalogue export` produces valid CSV/JSON for audit tools

---

## Phase 5: Terraform Execution Engine

**Goal:** Wrapper that runs terraform init/plan/apply/destroy per module.

### Tasks

- [ ] **5.1** Create `internal/tf/` package:
  ```
  internal/tf/runner.go
  internal/tf/state.go
  internal/tf/vars.go
  ```
- [ ] **5.2** Implement `runner.go`:
  - `Init(workDir)` → `terraform init` in the working directory
  - `Plan(workDir, varFile)` → `terraform plan -var-file=<f> -out=plan.tfplan`
  - `Apply(workDir, planFile)` → `terraform apply plan.tfplan`
  - `Destroy(workDir, varFile)` → `terraform destroy -var-file=<f> -auto-approve`
  - `Output(workDir)` → `terraform output -json` → parse into map
  - Capture stdout/stderr; stream to user if --verbose
  - Return structured result: success/fail, outputs, error message
- [ ] **5.3** Implement `state.go`: State path management
  - Convention: `~/.mirage/state/<spoke-alias>/<module>/terraform.tfstate`
  - Modules: `scenario-N`, `forwarding`, `brain`, `detection-rules`, `roles`
  - Each module gets isolated state (blast radius containment)
  - Support future: remote backend config (S3 bucket per spoke)
- [ ] **5.4** Implement `vars.go`: Variable file assembly
  - Takes: resolved naming map + account_id + region + any extra vars
  - Writes: `<workdir>/resolved.tfvars`
  - Format: HCL-compatible key-value pairs
- [ ] **5.5** Handle assume-role for cross-account:
  - Before terraform calls in spoke context:
    - Set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
      from `sts:AssumeRole` on spoke deployment role
    - OR: generate a provider block with assume_role config
  - Clean up temp credentials after operation
- [ ] **5.6** Implement `--dry-run` mode:
  - Run init + plan but skip apply
  - Display plan output to user
  - Exit cleanly (no state changes)
- [ ] **5.7** Handle terraform not installed:
  - Check `terraform` in PATH at binary startup
  - If missing: clear error + link to install docs
  - Check minimum version (1.5+)

### Acceptance
- `terraform init/plan/apply/destroy` execute correctly via runner
- State isolated per spoke + per module (no cross-contamination)
- Assume-role correctly provides spoke credentials to terraform
- `--dry-run` shows plan without applying
- Missing terraform binary gives helpful error

---

## Phase 6: Scenario Deploy & Destroy

**Goal:** `mirage scenario deploy/destroy` — the core operational commands.

### Tasks

- [ ] **6.1** Create `internal/cmd/scenario.go`: Cobra subcommand group
- [ ] **6.2** Implement `scenario list`:
  - Call discovery.Scanner to list available scenarios
  - Cross-reference catalogue: mark which are deployed in which spoke
  - Flags: `--service`, `--category`, `--deployed`, `--json`
  - Output: table with N | name | service | category | deployed (spoke)
- [ ] **6.3** Implement `scenario show <n>`:
  - Fetch scenario.yaml manifest from template source
  - Display: name, description, attack path, resource types, detection events
  - If deployed: show resolved names + ARNs from catalogue
- [ ] **6.4** Implement `scenario deploy <n|--all>`:
  - Guard: role == spoke (refuse in hub)
  - Preflight checks:
    - Roles deployed? (config has role ARNs) → fail if not
    - Forwarding deployed? → warn if not (decoy won't alert)
    - Spoke authorized on hub bus? → warn if not
  - Naming resolution: resolve all resource names for scenario N
  - Template fetch: pull from source → cache → integrity check
  - Generate tfvars: write resolved.tfvars
  - Terraform: init → plan → (show plan if --dry-run, else apply)
  - Seed fake-data: post-apply, upload fake-data/* to deployed resources
    - S3: `aws s3 cp`
    - SSM: `aws ssm put-parameter`
    - DynamoDB: `aws dynamodb put-item`
  - Catalogue: register all resources with ARNs from terraform output
  - Audit: log operation (operator, timestamp, scenario, spoke, result)
  - Summary: print deployed resources table
- [ ] **6.5** Implement `--all` mode:
  - Discover all canonical scenarios from template source
  - Deploy sequentially (or parallel with `--parallel N` in future)
  - Skip already-deployed (idempotent — terraform handles no-change)
  - Summary: N deployed, N skipped, N failed
- [ ] **6.6** Implement `scenario destroy <n|--all>`:
  - Guard: role == spoke
  - Show resources from catalogue that will be destroyed
  - Confirm (always, even with --yes for destroy)
  - Clean seeded data first (delete S3 objects, etc.)
  - Terraform destroy (using isolated state)
  - Deregister from catalogue (mark destroyed, retain history)
  - Audit log
- [ ] **6.7** Implement `--skip-seed` flag:
  - Deploy terraform resources but don't upload fake-data
  - Use case: re-deploy after template update without re-seeding
- [ ] **6.8** Implement `--name-prefix` flag:
  - One-off override for naming.prefix (doesn't persist to config)
  - Useful for testing: `--name-prefix test` → "test-terraform-state-bucket"
- [ ] **6.9** Implement `scenario status [<n>]`:
  - For specified scenario (or all):
    - Is it deployed? (check catalogue + terraform state)
    - Is it monitored? (check detection rules in hub)
    - Last verified? (from catalogue)
    - Drift? (terraform plan shows changes?)

### Acceptance
- `mirage scenario deploy 1` deploys scenario 1 with correct naming
- Resources appear in catalogue with correct ARNs
- Fake-data uploaded to correct destinations
- `mirage scenario destroy 1` tears down cleanly
- `--all` processes all canonical scenarios
- `--dry-run` shows plan without applying
- Guard refuses deploy in hub account
- Preflight warns about missing forwarding/authorization

---

## Phase 7: Monitoring Orchestration

**Goal:** `mirage monitor` deploys the detection pipeline with enforced ordering.

### Tasks

- [ ] **7.1** Create `internal/cmd/monitor.go`: Cobra subcommand group
- [ ] **7.2** Create `internal/monitor/` package:
  ```
  internal/monitor/brain.go
  internal/monitor/rules.go
  internal/monitor/forwarding.go
  internal/monitor/authorize.go
  internal/monitor/subscribe.go
  ```
- [ ] **7.3** Create monitoring Terraform templates:
  ```
  templates/monitoring/brain/main.tf          (EventBus + Lambda + SNS + IAM)
  templates/monitoring/brain/variables.tf
  templates/monitoring/brain/outputs.tf
  templates/monitoring/detection-rules/main.tf (EventBridge rules → Lambda)
  templates/monitoring/detection-rules/variables.tf
  templates/monitoring/forwarding/main.tf     (2 forwarding rules + IAM)
  templates/monitoring/forwarding/variables.tf
  ```
- [ ] **7.4** Implement `monitor deploy`:
  - Guard: role == hub
  - Step 1: terraform apply brain module
    - Capture outputs: bus_arn, lambda_arn, sns_topic_arn, invoke_role_arn
  - Step 2: terraform apply detection-rules module
    - Input: brain outputs + catalogue ARNs (all deployed decoy resources)
    - Generate one EventBridge rule per deployed scenario
  - Step 3: Subscribe alert emails (from config.alerts.emails)
    - `aws sns subscribe --protocol email --endpoint <email>`
  - Step 4: Authorize spoke accounts on event bus
    - For each spoke in config: `aws events put-permission`
  - Flags: `--brain-only`, `--rules-only`, `--email`, `--authorize`
- [ ] **7.5** Implement detection rule generation from catalogue:
  - Read all resources from catalogue (across all spokes)
  - Group by scenario → generate EventBridge rule pattern per scenario
  - Rule matches: specific ARNs + specific API calls (from scenario.yaml detection section)
  - Write as Terraform locals or dynamic blocks
- [ ] **7.6** Implement `monitor forwarding`:
  - Guard: role == spoke
  - Preflight: is this spoke authorized on hub bus?
    - Check: `aws events describe-event-bus` in hub (or attempt test PutEvents)
    - Fail with: "Run `mirage monitor authorize <spoke>` in hub account first"
  - terraform apply forwarding module:
    - Input: hub bus ARN (from config), spoke account ID, decoy ARNs (from catalogue)
    - Creates: 2 EventBridge rules + forwarding IAM role
  - Update catalogue: spoke.forwarding_deployed = true
- [ ] **7.7** Implement `monitor authorize <spoke-id>`:
  - Guard: role == hub
  - `aws events put-permission --event-bus-name <bus> --principal <spoke-id>
    --statement-id AllowSpoke-<alias> --action events:PutEvents`
  - Idempotent (update if statement exists)
- [ ] **7.8** Implement `monitor subscribe <email>`:
  - Guard: role == hub
  - Get SNS topic ARN from brain terraform output
  - `aws sns subscribe --topic-arn <arn> --protocol email --endpoint <email>`
  - Print: "Confirmation email sent — recipient must click to activate"
- [ ] **7.9** Implement `monitor status`:
  - Brain module: deployed? Lambda healthy? (invoke dry test)
  - Detection rules: count vs expected (catalogue scenario count)
  - Bus permissions: list authorized accounts
  - SNS subscriptions: Confirmed vs PendingConfirmation
  - Output: health report
- [ ] **7.10** Implement `monitor destroy`:
  - Guard: role == hub
  - Confirm (show what will be destroyed)
  - terraform destroy: detection-rules first, then brain
  - Revoke all bus permissions
  - Note: does NOT destroy spoke forwarding (that's a spoke-side op)

### Acceptance
- `mirage monitor deploy` creates full detection pipeline in hub
- Detection rules correctly reference catalogue ARNs
- `mirage monitor forwarding` creates forwarding in spoke
- Preflight correctly blocks if spoke not authorized
- `monitor authorize` grants bus access
- `monitor status` shows accurate health report
- Deploy order enforced end-to-end

---

## Phase 8: End-to-End Status

**Goal:** `mirage status` — the reconciled cross-plane health view.

### Tasks

- [ ] **8.1** Create `internal/cmd/status.go`: top-level `status` command
- [ ] **8.2** Implement hub plane checks:
  - Brain terraform state exists + resources present
  - Detection rules count matches catalogue scenario count
  - Bus permissions include all config spokes
  - SNS subscriptions confirmed
- [ ] **8.3** Implement spoke plane checks (per spoke):
  - Forwarding module: deployed? 2 rules ENABLED?
  - Scenarios: deployed count vs expected from config
  - Catalogue consistency: entries vs terraform state
- [ ] **8.4** Implement matrix output:
  ```
  spoke | scenario | deployed | forwarded | rule | alert-path | last-verified
  ```
  - Color-coded: green=ok, red=broken, yellow=warning
  - `--json` mode: structured output for CI
- [ ] **8.5** Implement drift detection:
  - Run `terraform plan` (read-only) per module
  - If plan shows changes → flag as "drift detected"
  - Include in status output
- [ ] **8.6** Implement `--spoke <alias>` filter:
  - Show status for single spoke only
- [ ] **8.7** Implement `--full` flag:
  - Include ARN-level detail for each resource
  - Show exact rule patterns and Lambda config

### Acceptance
- `mirage status` produces accurate end-to-end matrix
- Broken chain detected (e.g., deployed but no forwarding)
- Drift flagged when terraform state differs from live
- `--json` produces parseable output
- Works across multiple spokes

---

## Phase 9: Verify (Synthetic Drill)

**Goal:** `mirage verify` — prove the alert path works end-to-end.

### Tasks

- [ ] **9.1** Create `internal/cmd/verify.go`
- [ ] **9.2** Create `internal/verify/` package:
  ```
  internal/verify/drill.go
  internal/verify/poll.go
  internal/verify/report.go
  ```
- [ ] **9.3** Implement `drill.go`: Inject synthetic event
  - Option A: `aws events put-events` with CloudTrail-shaped event
    - Tag event as drill: `"detail": {"mirage_drill": true}`
  - Option B: Perform single benign read on a decoy resource
    (e.g., `s3 head-object` on a decoy bucket)
  - Target selection: `--scenario <n>` → specific, or random from catalogue
- [ ] **9.4** Implement `poll.go`: Wait for alert delivery
  - Poll Lambda CloudWatch logs for invocation matching drill event
  - Check SNS delivery status (if available via CloudWatch metrics)
  - Timeout: configurable (`--timeout`, default 30s)
- [ ] **9.5** Implement `report.go`: PASS/FAIL + latency
  - Measure: event injection → Lambda invocation → SNS publish
  - Target latency: 8–12 seconds
  - Output: PASS (Xs) / FAIL (timeout or missing stage)
  - Update catalogue: last_verified = now() for tested scenario
- [ ] **9.6** Implement `--drill-notify` flag:
  - Before injecting: send SNS message to subscribers
    "⚠️ DRILL: Mirage verification in progress — next alert is a test"
  - After completion: send "Drill complete: PASS/FAIL"
- [ ] **9.7** Implement audit logging:
  - Log verify execution to catalogue operations_log
  - Record: who, when, which scenario, result, latency

### Acceptance
- `mirage verify` injects event and detects Lambda invocation
- Latency measured accurately
- PASS/FAIL clearly reported
- `--drill-notify` sends pre/post notifications
- Catalogue updated with last_verified timestamp
- Works with `--scenario N` and random selection

---

## Phase 10: Abuse Command (Controlled Attack Simulation)

**Goal:** `mirage scenario abuse <n>` — deliberate, auditable attacker sim.

### Tasks

- [ ] **10.1** Implement `scenario abuse <n>` in scenario.go:
  - Guard: role == spoke
  - NO `--all` flag accepted (hard error if attempted)
  - Print WARNING banner (red, bold, unmissable):
    ```
    ⚠️  WARNING: This command simulates a REAL ATTACK on scenario N.
    It WILL trigger actual alerts to SOC/subscribers.
    Operator: <principal>  |  Target: scenario-N  |  Spoke: <alias>
    ```
  - Double-confirm: prompt "Type scenario number to confirm: "
    (even if --yes was passed, still require typed confirmation)
- [ ] **10.2** Implement abuse chain execution:
  - Read scenario.yaml → attack_path section
  - Execute steps:
    - If scenario uses IAM role: `sts:AssumeRole` on lure role
    - Then: access decoy resource (GetObject, GetSecretValue, Scan, etc.)
  - These actions trigger real CloudTrail events → real alerts
- [ ] **10.3** Implement post-abuse output:
  - Print: "Attack simulation complete. Real alert delivered."
  - Print: "Check SOC inbox within ~12 seconds."
  - Log to catalogue: abuse operation with full context
- [ ] **10.4** Ensure abuse CANNOT be batched:
  - Reject `--all` with clear error
  - Reject multiple positional args
  - One scenario per invocation, always

### Acceptance
- `mirage scenario abuse 3` triggers real detection
- Cannot run on multiple scenarios at once
- Double-confirmation required (type the number)
- Full audit trail in catalogue
- SOC receives real alert within expected latency

---

## Phase 11: Polish & Release

**Goal:** Production-ready binary with CI, docs, and distribution.

### Tasks

- [ ] **11.1** Shell completion: generate bash/zsh/fish completions
  - `mirage completion bash|zsh|fish`
- [ ] **11.2** Version command: `mirage version`
  - Embed git commit + build date via ldflags
- [ ] **11.3** Error handling audit:
  - Every command returns meaningful exit codes (0=success, 1=error, 2=guard)
  - Error messages include: what failed, why, what to do next
  - No stack traces in non-verbose mode
- [ ] **11.4** Colour output:
  - Green: success, healthy
  - Yellow: warning, degraded
  - Red: error, broken
  - Respect `NO_COLOR` env var (disable colours in CI)
- [ ] **11.5** CI pipeline (GitHub Actions):
  - `go test ./...` on every push
  - `golangci-lint` for code quality
  - Build binaries for linux/amd64, darwin/amd64, darwin/arm64
  - Release on tag push (goreleaser)
- [ ] **11.6** README.md for the binary repo:
  - Installation (homebrew tap + direct download)
  - Quick start guide (init → roles → monitor → scenario)
  - Link to design docs (this folder)
- [ ] **11.7** Man page / `--help` text for every command:
  - Short description + example usage + related commands
- [ ] **11.8** Integration test suite:
  - Uses localstack or mocked AWS for CI
  - Tests: init → roles → deploy scenario → verify → destroy lifecycle
- [ ] **11.9** Security hardening review:
  - No secrets logged (even in --verbose)
  - Temp credentials cleaned up after use
  - Config file permissions: 0600 (user-only read/write)
  - SQLite DB permissions: 0600

### Acceptance
- Binary cross-compiles for all targets
- CI green on all tests
- `--help` clear and useful for every command
- Integration tests pass the full lifecycle
- No credentials leaked in logs or output

---

## Dependency Summary

```
Phase 0 (scaffold)
    │
    ▼
Phase 1 (init) ──────────────────────────────────────┐
    │                                                  │
    ▼                                                  │
Phase 2 (roles) ←── needs config from Phase 1         │
    │                                                  │
    ├──────────────────────┐                           │
    ▼                      ▼                           │
Phase 3 (naming+templates) Phase 4 (catalogue)        │
    │                      │                           │
    └──────────┬───────────┘                           │
               ▼                                       │
         Phase 5 (terraform engine)                    │
               │                                       │
    ┌──────────┼──────────┐                            │
    ▼          ▼          ▼                            │
Phase 6    Phase 7    Phase 8                          │
(scenario) (monitor)  (status) ←───────────────────────┘
    │          │          │
    └──────────┼──────────┘
               ▼
         Phase 9 (verify)
               │
               ▼
         Phase 10 (abuse)
               │
               ▼
         Phase 11 (polish)
```

---

## Quick Reference: What to Build First

| Priority | Phase | Commands unlocked | Risk level |
|----------|-------|-------------------|------------|
| 1 | Phase 0+1 | `init`, `config show/set` | Zero (local only) |
| 2 | Phase 2 | `roles deploy/import/status` | Low (IAM only) |
| 3 | Phase 3+4+5 | (internal — no new commands) | Zero (libraries) |
| 4 | Phase 6 | `scenario list/show/deploy/destroy` | Medium (creates resources) |
| 5 | Phase 7 | `monitor deploy/forwarding/authorize` | Medium (detection pipeline) |
| 6 | Phase 8 | `status` | Zero (read-only) |
| 7 | Phase 9 | `verify` | Low (synthetic events) |
| 8 | Phase 10 | `scenario abuse` | High (real alerts) |
| 9 | Phase 11 | (all — production quality) | Zero (polish) |

---

## Notes for Gemini

- Each phase should produce a **compilable, testable binary** — don't leave broken code between phases.
- Write unit tests alongside implementation (not after). Test the guard, naming resolver, and catalogue operations thoroughly.
- Use interfaces for AWS calls (`internal/awsctx/`) so tests can mock STS/EventBridge/SNS without live AWS.
- Terraform templates are **separate artifacts** — they live in their own repo/directory. The binary fetches them.
- The naming resolver is the most architecturally important piece — get it right in Phase 3. Everything downstream depends on it.
- Catalogue audit trail is non-negotiable — every mutation must be logged before it's considered "done."
- When in doubt about what a command should do: check `SINGLE-PAGE-FLOW.md` and `02-command-tree.md`.
