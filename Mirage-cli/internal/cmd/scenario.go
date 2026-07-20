package cmd

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/fatih/color"
	"github.com/mirage-security/mirage/internal/abuse"
	"github.com/mirage-security/mirage/internal/awsctx"
	"github.com/mirage-security/mirage/internal/catalogue"
	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/discovery"
	"github.com/mirage-security/mirage/internal/naming"
	"github.com/mirage-security/mirage/internal/seeder"
	"github.com/mirage-security/mirage/internal/templates"
	"github.com/mirage-security/mirage/internal/tf"
	"github.com/mirage-security/mirage/pkg/models"
	"github.com/spf13/cobra"
)

func newScenarioCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "scenario",
		Short: "Manage deception scenarios (honeypots, lures, decoys)",
		Long: `Deploy and manage the 19 AWS deception scenarios.

Available scenarios:
  S3 + IAM          : Terraform state lure, deploy keys
  Secrets Manager   : Payment gateway credentials
  EC2               : Bastion host breadcrumbs
  ECR               : Container registry lure
  Lambda            : Hardcoded secrets, code injection
  IAM               : Role chain loop, SAML/Okta SSO
  DynamoDB          : Customer profiles, session tokens
  SQS               : Payment events DLQ
  SNS               : Critical alerts topic
  CloudWatch Logs   : Accidentally-logged credentials
  KMS               : Customer data encryption key
  SSM               : Cross-reference parameter chains
  CloudFormation    : Exposed stack outputs`,
	}

	cmd.AddCommand(newScenarioListCmd())
	cmd.AddCommand(newScenarioShowCmd())
	cmd.AddCommand(newScenarioDeployCmd())
	cmd.AddCommand(newScenarioDestroyCmd())
	cmd.AddCommand(newScenarioAbuseCmd())
	cmd.AddCommand(newScenarioStatusCmd())
	return cmd
}

func newScenarioListCmd() *cobra.Command {
	var (
		flagService  string
		flagCategory string
		flagDeployed bool
	)
	cmd := &cobra.Command{
		Use:   "list",
		Short: "List available deception scenarios",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load()
			if err != nil {
				return err
			}

			scanner := discovery.NewScanner(cfg.Templates.Local.Path)
			scenarios, err := scanner.ScanAll()
			if err != nil {
				return fmt.Errorf("failed to scan templates: %w", err)
			}

			// If looking for deployed, check the catalogue
			var deployedMap map[int]bool
			if flagDeployed {
				deployedMap = make(map[int]bool)
				
				ctx := context.Background()
				identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
				if err == nil {
					store, err := catalogue.NewSQLiteStore(cfg.Catalogue.SQLitePath)
					if err == nil {
						defer store.Close()
						resources, err := store.ListResources(ctx, catalogue.ResourceFilter{
							AccountID: identity.AccountID,
							Status:    "active",
						})
						if err == nil {
							for _, r := range resources {
								deployedMap[r.ScenarioNum] = true
							}
						}
					}
				}
			}

			color.New(color.Bold).Printf("\n%-4s %-25s %-20s %-20s\n", "NUM", "NAME", "SERVICE", "CATEGORY")
			fmt.Println(strings.Repeat("─", 80))

			for _, s := range scenarios {
				// Apply filters
				if flagService != "" && !strings.EqualFold(s.Service, flagService) {
					continue
				}
				if flagCategory != "" && !strings.EqualFold(s.Category, flagCategory) {
					continue
				}
				if flagDeployed && !deployedMap[s.Number] {
					continue
				}

				fmt.Printf("%-4d %-25s %-20s %-20s\n", s.Number, s.Name, s.Service, s.Category)
			}
			fmt.Println()
			return nil
		},
	}
	cmd.Flags().StringVar(&flagService, "service", "", "Filter by service (s3, iam, lambda, etc.)")
	cmd.Flags().StringVar(&flagCategory, "category", "", "Filter by category (credential-theft, data-exfil, lateral-movement, privilege-escalation)")
	cmd.Flags().BoolVar(&flagDeployed, "deployed", false, "Show only deployed scenarios")
	return cmd
}

func newScenarioShowCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "show <n>",
		Short: "Show scenario details, attack path, and detection events",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load()
			if err != nil {
				return err
			}

			num, err := strconv.Atoi(args[0])
			if err != nil {
				return fmt.Errorf("invalid scenario number %q", args[0])
			}

			scanner := discovery.NewScanner(cfg.Templates.Local.Path)
			manifest, err := scanner.GetScenario(num)
			if err != nil {
				return fmt.Errorf("failed to load scenario %d: %w", num, err)
			}

			bold := color.New(color.Bold)
			cyan := color.New(color.FgCyan)

			fmt.Println()
			bold.Printf("Scenario %d: %s\n", manifest.Number, manifest.Name)
			fmt.Println(strings.Repeat("=", 60))
			fmt.Printf("Category:    %s\n", manifest.Category)
			fmt.Printf("Service:     %s\n", manifest.Service)
			fmt.Printf("Description: %s\n", manifest.Description)
			
			fmt.Println("\nResources Deployed:")
			for _, r := range manifest.Resources {
				fmt.Printf("  - %-15s : %s\n", r.Type, r.Purpose)
			}

			if len(manifest.Seed) > 0 {
				fmt.Println("\nSeeded Data:")
				for _, s := range manifest.Seed {
					fmt.Printf("  - %-15s : %s\n", s.Kind, s.DestinationKey)
				}
			}

			fmt.Println("\nDetection Triggers:")
			fmt.Printf("  Severity: %s\n", manifest.Detection.Severity)
			for _, event := range manifest.Detection.Events {
				fmt.Printf("  - %s / %s (API: %s)\n", 
					event.Source, 
					event.DetailType, 
					strings.Join(event.APICalls, ", "))
			}

			if len(manifest.AttackPath) > 0 {
				fmt.Println("\nExpected Attack Path:")
				for i, step := range manifest.AttackPath {
					cyan.Printf("  %d. %s\n", i+1, step)
				}
			}

			fmt.Println()
			return nil
		},
	}
}

func newScenarioDeployCmd() *cobra.Command {
	var (
		flagAll        bool
		flagSkipSeed   bool
		flagNamePrefix string
	)
	cmd := &cobra.Command{
		Use:   "deploy [n] [--all]",
		Short: "Deploy a deception scenario into the current spoke account",
		Long: `Deploys one or all deception scenarios.

Flow:
  1. Account-role guard (must be spoke)
  2. Preflight checks (roles, forwarding, bus auth)
  3. Resolve resource names from config
  4. Fetch + verify Terraform template
  5. terraform init → plan → apply
  6. Seed fake data into deployed resources
  7. Register all resources in catalogue
  8. Audit log the operation

Guard: must be run from a SPOKE account.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			// Preflight 1: Account-role guard (must be spoke)
			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			if err := awsctx.RequireSpoke(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}
			spoke, err := cfg.GetSpoke(identity.AccountID)
			if err != nil {
				return fmt.Errorf("current account %s not found in spoke config", identity.AccountID)
			}

			// Preflight 2: Roles deployed
			if !spoke.RolesDeployed {
				return fmt.Errorf("spoke %s has not had roles deployed yet; run `mirage roles deploy` from the hub", spoke.Alias)
			}

			// Determine which scenarios to deploy
			var numsToDeploy []int
			if flagAll {
				for i := 1; i <= 19; i++ {
					numsToDeploy = append(numsToDeploy, i)
				}
			} else {
				if len(args) == 0 {
					return fmt.Errorf("specify a scenario number or --all")
				}
				num, err := strconv.Atoi(args[0])
				if err != nil {
					return fmt.Errorf("invalid scenario number %q", args[0])
				}
				numsToDeploy = append(numsToDeploy, num)
			}
			// Build deploy jobs based on config instances
			type deployJob struct {
				num        int
				instanceID string
				randomize  bool
				overrides  map[string]string
			}
			var jobs []deployJob
			
			configuredInstances := make(map[int]config.Instance)
			for _, inst := range cfg.Deception.Instances {
				configuredInstances[inst.Scenario] = inst
			}
			
			for _, num := range numsToDeploy {
				inst, ok := configuredInstances[num]
				if !ok {
					jobs = append(jobs, deployJob{num: num, instanceID: "default"})
					continue
				}
				count := inst.Count
				if count < 1 {
					count = 1
				}
				for i := 1; i <= count; i++ {
					instanceID := "default"
					if count > 1 {
						instanceID = fmt.Sprintf("instance-%d", i)
					}
					jobs = append(jobs, deployJob{
						num:        num,
						instanceID: instanceID,
						randomize:  inst.Randomize || count > 1,
						overrides:  inst.Overrides,
					})
				}
			}
			// Set up discovery and fetching
			source := templates.SourceFromConfig(cfg.Templates.Local.Path, "", "")
			fetcher := templates.NewFetcher(source, filepath.Join(config.MirageDir(), "templates"))
			scanner := discovery.NewScanner(cfg.Templates.Local.Path)
			
			// Setup catalogue
			store, err := catalogue.NewSQLiteStore(cfg.Catalogue.SQLitePath)
			if err != nil {
				return fmt.Errorf("open catalogue: %w", err)
			}
			defer store.Close()

			resolver := naming.NewResolver(cfg, identity.AccountID, cfg.Region, spoke.Alias)
			if flagNamePrefix != "" {
				resolver.WithFlagPrefix(flagNamePrefix)
			}

			awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			stsClient := sts.NewFromConfig(awsCfg)
			
			// We deploy into the spoke directly since we are currently logged into it.
			// Therefore runner doesn't need cross-account assume.
			runner := tf.NewRunner(GlobalVerbose)
			if err := tf.CheckInstalled(); err != nil {
				return err
			}

			for _, job := range jobs {
				num := job.num
				color.New(color.Bold).Printf("\n▶ Deploying Scenario %d (%s)\n", num, job.instanceID)
				
				stateModule := naming.ScenarioKey(num)
				if job.instanceID != "default" {
					stateModule = filepath.Join(naming.ScenarioKey(num), job.instanceID)
				}
				statePath := tf.StatePath(config.MirageDir(), "scenarios", spoke.Alias, stateModule)
				
				// Singleton Database Check
				activeRes, _ := store.ListResources(ctx, catalogue.ResourceFilter{
					AccountID:   identity.AccountID,
					ScenarioNum: num,
					Status:      "active",
				})
				alreadyDeployed := false
				for _, r := range activeRes {
					if r.TFStatePath == statePath {
						alreadyDeployed = true
						break
					}
				}
				if alreadyDeployed {
					color.Yellow("  ⚠ Instance %s is already deployed. Skipping.", job.instanceID)
					continue
				}
				
				if err := fetcher.Ensure(num); err != nil {
					color.Red("  ✗ Template fetch failed: %v", err)
					continue
				}

				manifest, err := scanner.GetScenario(num)
				if err != nil {
					color.Red("  ✗ Parse scenario.yaml failed: %v", err)
					continue
				}

				color.Cyan("  %s - %s", manifest.Name, manifest.Description)
				
				// Resolve Names & TFVars
				resolved := make(map[string]string)
				var resolutionErr error
				for _, r := range manifest.Resources {
					extraVars := make(map[string]string)
					if r.Key != "" {
						extraVars["key"] = r.Key
					} else {
						extraVars["key"] = r.TFVariable
					}
					if job.overrides != nil {
						if val, hasOverride := job.overrides[r.Type]; hasOverride {
							extraVars["key"] = val
						}
					}
					name, err := resolver.Resolve(naming.ScenarioKey(num), r.Type, manifest.Slug, extraVars)
					if err != nil {
						resolutionErr = fmt.Errorf("resolve %s: %w", r.Type, err)
						break
					}
					if job.randomize {
						name = fmt.Sprintf("%s-%s", name, naming.RandomSuffix())
					}
					resolved[r.TFVariable] = name
				}

				if resolutionErr != nil {
					color.Red("  ✗ Naming resolution failed: %v", resolutionErr)
					continue
				}

				tfVarsContent, err := naming.GenerateTFVars(
					manifest.Terraform.RequiredVariables, 
					resolved, 
					identity.AccountID, 
					cfg.Region, 
					nil)
				if err != nil {
					color.Red("  ✗ TFVars generation failed: %v", err)
					continue
				}

				scenarioDir := fetcher.ScenarioDir(num)
				tfVarsPath := filepath.Join(scenarioDir, "resolved.auto.tfvars")
				if err := naming.WriteTFVars(tfVarsPath, tfVarsContent); err != nil {
					color.Red("  ✗ Write tfvars failed: %v", err)
					continue
				}

				// Terraform Apply
				if err := tf.EnsureStateDir(statePath); err != nil {
					color.Red("  ✗ State dir creation failed: %v", err)
					continue
				}
				
				if err := tf.WriteBackendOverride(scenarioDir, statePath); err != nil {
					color.Red("  ✗ Write backend override failed: %v", err)
					continue
				}
				
				res, err := runner.ApplyWithVars(ctx, scenarioDir, nil, GlobalDryRun)
				
				tf.RemoveBackendOverride(scenarioDir) // cleanup override
				os.Remove(tfVarsPath) // cleanup vars
				
				if err != nil {
					color.Red("  ✗ Terraform apply failed: %v", err)
					continue
				}
				
				if GlobalDryRun {
					color.Yellow("  ✓ Plan complete (dry-run)")
					continue
				}

				// Seeder
				if !flagSkipSeed && len(manifest.Seed) > 0 {
					color.Blue("  Seeding fake data...")
					seederClient := seeder.New(awsCfg)
					seedRes := seederClient.SeedAll(ctx, manifest, res.Outputs, scenarioDir)
					for _, sr := range seedRes {
						if !sr.OK {
							color.Yellow("    ⚠ Seed %s %s failed: %v", sr.Kind, sr.Key, sr.Err)
						}
					}
				}

				// Catalogue Registration
				color.Blue("  Registering resources in catalogue...")
				for _, r := range manifest.Resources {
					var arn string
					// Check if ARN is in outputs
					for k, v := range res.Outputs {
						if strings.Contains(k, r.TFVariable) && strings.Contains(k, "arn") {
							arn = v
							break
						}
					}
					
					resourceName := resolved[r.TFVariable]
					_, err := store.RegisterResource(ctx, models.Resource{
						AccountID:    identity.AccountID,
						SpokeAlias:   spoke.Alias,
						ScenarioNum:  num,
						ScenarioName: manifest.Name,
						ResourceType: r.Type,
						ResourceName: resourceName,
						ARN:          arn,
						DeployedAt:   time.Now(),
						DeployedBy:   identity.UserID,
						TFStatePath:  statePath,
						Status:       "active",
					})
					if err != nil {
						color.Yellow("    ⚠ Failed to register resource %s: %v", resourceName, err)
					}
				}
				
				// Audit Log
				callerIdentity, _ := stsClient.GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
				arn := "unknown"
				if callerIdentity != nil {
					arn = *callerIdentity.Arn
				}
				
				err = store.LogOperation(ctx, models.Operation{
					Timestamp:   time.Now(),
					Operator:    arn,
					Command:     "scenario deploy",
					AccountID:   identity.AccountID,
					SpokeAlias:  spoke.Alias,
					ScenarioNum: num,
					Action:      "deploy",
					Result:      "success",
					Details:     "deployed successfully",
				})
				if err != nil {
					color.Yellow("  ⚠ Failed to write audit log: %v", err)
				}

				color.Green("  ✓ Scenario %d deployed successfully", num)
			}

			return nil
		},
	}
	cmd.Flags().BoolVar(&flagAll, "all", false, "Deploy all canonical scenarios")
	cmd.Flags().BoolVar(&flagSkipSeed, "skip-seed", false, "Skip fake-data seeding after deploy")
	cmd.Flags().StringVar(&flagNamePrefix, "name-prefix", "", "One-off naming prefix override (does not persist to config)")
	return cmd
}

func newScenarioDestroyCmd() *cobra.Command {
	var flagAll bool
	cmd := &cobra.Command{
		Use:   "destroy [n] [--all]",
		Short: "Destroy a deployed deception scenario",
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			// Preflight: Account-role guard
			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			if err := awsctx.RequireSpoke(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}
			spoke, err := cfg.GetSpoke(identity.AccountID)
			if err != nil {
				return fmt.Errorf("current account %s not found in spoke config", identity.AccountID)
			}

			// Determine which scenarios to destroy
			var numsToDestroy []int
			if flagAll {
				for i := 1; i <= 19; i++ {
					numsToDestroy = append(numsToDestroy, i)
				}
			} else {
				if len(args) == 0 {
					return fmt.Errorf("specify a scenario number or --all")
				}
				num, err := strconv.Atoi(args[0])
				if err != nil {
					return fmt.Errorf("invalid scenario number %q", args[0])
				}
				numsToDestroy = append(numsToDestroy, num)
			}
			// Build destroy jobs based on config instances
			type destroyJob struct {
				num        int
				instanceID string
				randomize  bool
				overrides  map[string]string
			}
			var jobs []destroyJob
			
			configuredInstances := make(map[int]config.Instance)
			for _, inst := range cfg.Deception.Instances {
				configuredInstances[inst.Scenario] = inst
			}
			
			for _, num := range numsToDestroy {
				inst, ok := configuredInstances[num]
				if !ok {
					jobs = append(jobs, destroyJob{num: num, instanceID: "default"})
					continue
				}
				count := inst.Count
				if count < 1 {
					count = 1
				}
				for i := 1; i <= count; i++ {
					instanceID := "default"
					if count > 1 {
						instanceID = fmt.Sprintf("instance-%d", i)
					}
					jobs = append(jobs, destroyJob{
						num:        num,
						instanceID: instanceID,
						randomize:  inst.Randomize || count > 1,
						overrides:  inst.Overrides,
					})
				}
			}
			source := templates.SourceFromConfig(cfg.Templates.Local.Path, "", "")
			fetcher := templates.NewFetcher(source, filepath.Join(config.MirageDir(), "templates"))
			scanner := discovery.NewScanner(cfg.Templates.Local.Path)
			
			store, err := catalogue.NewSQLiteStore(cfg.Catalogue.SQLitePath)
			if err != nil {
				return fmt.Errorf("open catalogue: %w", err)
			}
			defer store.Close()

			resolver := naming.NewResolver(cfg, identity.AccountID, cfg.Region, spoke.Alias)
			
			awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			stsClient := sts.NewFromConfig(awsCfg)

			runner := tf.NewRunner(GlobalVerbose)

			for _, job := range jobs {
				num := job.num
				color.New(color.Bold).Printf("\n▶ Destroying Scenario %d (%s)\n", num, job.instanceID)

				manifest, err := scanner.GetScenario(num)
				if err != nil {
					color.Red("  ✗ Parse scenario.yaml failed: %v", err)
					continue
				}

				// Resolve Names & TFVars
				resolved := make(map[string]string)
				var resolutionErr error
				for _, r := range manifest.Resources {
					extraVars := make(map[string]string)
					if r.Key != "" {
						extraVars["key"] = r.Key
					} else {
						extraVars["key"] = r.TFVariable
					}
					if job.overrides != nil {
						if val, hasOverride := job.overrides[r.Type]; hasOverride {
							extraVars["key"] = val
						}
					}
					name, err := resolver.Resolve(naming.ScenarioKey(num), r.Type, manifest.Slug, extraVars)
					if err != nil {
						resolutionErr = fmt.Errorf("resolve %s: %w", r.Type, err)
						break
					}
					if job.randomize {
						name = fmt.Sprintf("%s-%s", name, naming.RandomSuffix())
					}
					resolved[r.TFVariable] = name
				}

				if resolutionErr != nil {
					color.Red("  ✗ Naming resolution failed: %v", resolutionErr)
					continue
				}

				tfVarsContent, err := naming.GenerateTFVars(
					manifest.Terraform.RequiredVariables, 
					resolved, 
					identity.AccountID, 
					cfg.Region, 
					nil)
				if err != nil {
					color.Red("  ✗ TFVars generation failed: %v", err)
					continue
				}

				scenarioDir := fetcher.ScenarioDir(num)
				tfVarsPath := filepath.Join(scenarioDir, "resolved.auto.tfvars")
				if err := naming.WriteTFVars(tfVarsPath, tfVarsContent); err != nil {
					color.Red("  ✗ Write tfvars failed: %v", err)
					continue
				}

				stateModule := naming.ScenarioKey(num)
				if job.instanceID != "default" {
					stateModule = filepath.Join(naming.ScenarioKey(num), job.instanceID)
				}
				statePath := tf.StatePath(config.MirageDir(), "scenarios", spoke.Alias, stateModule)
				if !tf.StateExists(statePath) {
					color.Yellow("  ⚠ No Terraform state found for scenario %d. Skipping destroy.", num)
					continue
				}
				
				if err := tf.WriteBackendOverride(scenarioDir, statePath); err != nil {
					color.Red("  ✗ Write backend override failed: %v", err)
					continue
				}
				
				_, err = runner.DestroyWithVars(ctx, scenarioDir, nil, GlobalDryRun)
				
				tf.RemoveBackendOverride(scenarioDir) // cleanup override
				os.Remove(tfVarsPath) // cleanup vars
				
				if err != nil {
					color.Red("  ✗ Terraform destroy failed: %v", err)
					continue
				}
				
				if GlobalDryRun {
					color.Yellow("  ✓ Plan complete (dry-run)")
					continue
				}

				// Catalogue Deregistration
				color.Blue("  Updating catalogue...")
				
				callerIdentity, _ := stsClient.GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
				arn := "unknown"
				if callerIdentity != nil {
					arn = *callerIdentity.Arn
				}
				
				resources, err := store.ListResources(ctx, catalogue.ResourceFilter{
					AccountID:   identity.AccountID,
					ScenarioNum: num,
					Status:      "active",
				})
				if err == nil {
					for _, r := range resources {
						if err := store.DeregisterResource(ctx, r.ID, arn); err != nil {
							color.Yellow("    ⚠ Failed to deregister resource %s: %v", r.ResourceName, err)
						}
					}
				}
				
				// Audit Log
				err = store.LogOperation(ctx, models.Operation{
					Timestamp:   time.Now(),
					Operator:    arn,
					Command:     "scenario destroy",
					AccountID:   identity.AccountID,
					SpokeAlias:  spoke.Alias,
					ScenarioNum: num,
					Action:      "destroy",
					Result:      "success",
					Details:     "destroyed successfully",
				})
				if err != nil {
					color.Yellow("  ⚠ Failed to write audit log: %v", err)
				}

				color.Green("  ✓ Scenario %d destroyed successfully", num)
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&flagAll, "all", false, "Destroy all deployed scenarios")
	return cmd
}

// newScenarioAbuseCmd is the most safety-critical command — see Phase 10.
func newScenarioAbuseCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "abuse <n>",
		Short: "⚠ Simulate a REAL attack on scenario N (triggers live alerts)",
		Long: color.RedString(`
  ██╗    ██╗ █████╗ ██████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
  ██║    ██║██╔══██╗██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
  ██║ █╗ ██║███████║██████╔╝██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
  ██║███╗██║██╔══██║██╔══██╗██║╚██╗██║██║██║╚██╗██║██║   ██║
  ╚███╔███╔╝██║  ██║██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝`) + `

This command executes a REAL attack chain against a deception scenario.
It WILL trigger actual alerts to your SOC and all subscribers.

  • --all is not supported and will be rejected
  • Double confirmation required (even with --yes)
  • Full audit trail logged with operator identity
  • Notify your SOC before running: use --drill-notify

Guard: must be run from a SPOKE account.`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			// Preflight: Account-role guard
			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			if err := awsctx.RequireSpoke(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}
			spoke, err := cfg.GetSpoke(identity.AccountID)
			if err != nil {
				return fmt.Errorf("current account %s not found in spoke config", identity.AccountID)
			}

			num, err := strconv.Atoi(args[0])
			if err != nil {
				return fmt.Errorf("invalid scenario number %q", args[0])
			}

			color.Red("\n  ██╗    ██╗ █████╗ ██████╗ ██████╗ ██╗███╗   ██╗ ██████╗")
			color.Red("  ██║    ██║██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║██╔════╝")
			color.Red("  ██║ █╗ ██║███████║██████╔╝██║  ██║██║██╔██╗ ██║██║  ███╗")
			color.Red("  ██║███╗██║██╔══██║██╔══██╗██║  ██║██║██║╚██╗██║██║   ██║")
			color.Red("  ╚███╔███╔╝██║  ██║██║  ██║██████╔╝██║██║ ╚████║╚██████╔╝")
			color.Red("   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝\n")

			color.Yellow("⚠️  WARNING: This command simulates a REAL ATTACK on scenario %d.", num)
			color.Yellow("It WILL trigger actual alerts to SOC/subscribers.")
			color.Yellow("Operator: %s  |  Target: scenario-%d  |  Spoke: %s", identity.ARN, num, spoke.Alias)
			
			fmt.Printf("\nType scenario number (%d) to confirm: ", num)
			var confirmation string
			fmt.Scanln(&confirmation)
			if confirmation != strconv.Itoa(num) {
				return fmt.Errorf("confirmation failed. aborting attack simulation")
			}

			awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			store, err := catalogue.NewSQLiteStore(cfg.Catalogue.SQLitePath)
			if err != nil {
				return fmt.Errorf("open catalogue: %w", err)
			}
			defer store.Close()

			return abuse.RunAttack(ctx, abuse.AttackConfig{
				AWSConfig:     awsCfg,
				Catalogue:     store,
				TemplatesPath: cfg.Templates.Local.Path,
				TargetScenario: num,
				Identity:      identity,
				SpokeAlias:    spoke.Alias,
			})
		},
	}
	// Deliberately NO --all flag.
	return cmd
}

func newScenarioStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status [n]",
		Short: "Show deployment and monitoring health for scenario(s)",
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			// Preflight: Account-role guard
			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			if err := awsctx.RequireSpoke(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			store, err := catalogue.NewSQLiteStore(cfg.Catalogue.SQLitePath)
			if err != nil {
				return fmt.Errorf("open catalogue: %w", err)
			}
			defer store.Close()

			var targetNum int
			if len(args) > 0 {
				targetNum, _ = strconv.Atoi(args[0])
			}

			resources, err := store.ListResources(ctx, catalogue.ResourceFilter{
				AccountID:   identity.AccountID,
				ScenarioNum: targetNum, // 0 = all
				Status:      "active",
			})
			if err != nil {
				return fmt.Errorf("list resources: %w", err)
			}

			if len(resources) == 0 {
				fmt.Println("No active scenarios found.")
				return nil
			}

			scanner := discovery.NewScanner(cfg.Templates.Local.Path)
			manifests, err := scanner.ScanAll()
			if err != nil {
				return fmt.Errorf("failed to scan templates: %w", err)
			}

			manifestMap := make(map[int]*models.ScenarioManifest)
			for _, m := range manifests {
				manifestMap[m.Number] = m
			}

			// Group resources by scenario number
			scenarios := make(map[int][]models.Resource)
			for _, r := range resources {
				scenarios[r.ScenarioNum] = append(scenarios[r.ScenarioNum], r)
			}

			fmt.Println("\nStatus for Deployed Scenarios:")
			fmt.Println(strings.Repeat("=", 80))

			for num, resList := range scenarios {
				m := manifestMap[num]
				if m == nil {
					continue
				}

				fmt.Printf("\n▶ Scenario %d: %s\n", num, m.Name)
				fmt.Printf("  Deployed Resources (%d):\n", len(resList))
				for _, r := range resList {
					fmt.Printf("  - %-25s: %s\n", r.ResourceName, r.ARN)
				}
			}
			
			fmt.Println()
			return nil
		},
	}
}
