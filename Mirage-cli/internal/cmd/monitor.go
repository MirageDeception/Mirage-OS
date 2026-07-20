package cmd

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/fatih/color"
	"github.com/mirage-security/mirage/internal/awsctx"
	"github.com/mirage-security/mirage/internal/catalogue"
	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/discovery"
	"github.com/mirage-security/mirage/internal/monitor"
	"github.com/spf13/cobra"
)

func newMonitorCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "monitor",
		Short: "Deploy and manage the detection pipeline (hub account)",
		Long: `Orchestrate the monitoring architecture in the hub account.

Deploy order (enforced):
  1. monitor deploy        hub: EventBus + Lambda + SNS + detection rules
  2. monitor authorize     hub: grant spoke(s) bus access
  3. monitor forwarding    spoke: forwarding rules → hub bus
  4. scenario deploy       spoke: deploy decoy resources

Guard: monitor deploy/authorize/subscribe/destroy require HUB account.
       monitor forwarding requires SPOKE account.`,
	}

	cmd.AddCommand(newMonitorDeployCmd())
	cmd.AddCommand(newMonitorForwardingCmd())
	cmd.AddCommand(newMonitorAuthorizeCmd())
	cmd.AddCommand(newMonitorSubscribeCmd())
	cmd.AddCommand(newMonitorStatusCmd())
	cmd.AddCommand(newMonitorDestroyCmd())
	return cmd
}

func newMonitorDeployCmd() *cobra.Command {
	var (
		flagBrainOnly bool
		flagRulesOnly bool
	)
	cmd := &cobra.Command{
		Use:   "deploy",
		Short: "Deploy the full detection pipeline in the hub account",
		Long: `Deploys in order:
  [1] Brain module: EventBus + Lambda processor + SNS + IAM
  [2] Detection rules: EventBridge rules referencing catalogue ARNs
  [3] Subscribe alert emails (from config.alerts.emails)
  [4] Authorize spoke accounts on event bus

Guard: must be run from the HUB account.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			if err := awsctx.RequireHub(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			if !flagRulesOnly {
				color.New(color.Bold).Println("\n▶ Deploying Brain Module")
				
				repoRoot, err := findRepoRoot()
				if err != nil {
					return err
				}
				templatesDir := filepath.Join(repoRoot, "Mirage-cli", "templates", "monitoring")

				outputs, err := monitor.DeployBrain(ctx, cfg, templatesDir, GlobalDryRun)
				if err != nil {
					return fmt.Errorf("failed to deploy brain: %w", err)
				}
				
				// Update config with outputs
				if !GlobalDryRun {
					cfg.Monitoring.EventBusARN = outputs["event_bus_arn"]
					cfg.Monitoring.SNSTopicARN = outputs["sns_topic_arn"]
					cfg.Monitoring.BrainLambdaARN = outputs["lambda_arn"]
					if err := config.Save(cfg); err != nil {
						color.Yellow("⚠ Failed to save monitor outputs to config: %v", err)
					}
					color.Green("✓ Brain deployed successfully.")
				}
			}

			if !flagBrainOnly {
				color.New(color.Bold).Println("\n▶ Deploying Detection Rules")
				store, err := catalogue.NewSQLiteStore(cfg.Catalogue.SQLitePath)
				if err != nil {
					return fmt.Errorf("open catalogue: %w", err)
				}
				defer store.Close()
				
				scanner := discovery.NewScanner(cfg.Templates.Local.Path)
				
				if err := monitor.DeployRules(ctx, cfg, store, scanner, GlobalDryRun); err != nil {
					return fmt.Errorf("failed to deploy rules: %w", err)
				}
				
				if !GlobalDryRun {
					color.Green("✓ Detection rules updated successfully.")
				}
			}

			return nil
		},
	}
	cmd.Flags().BoolVar(&flagBrainOnly, "brain-only", false, "Deploy brain module only (skip rules)")
	cmd.Flags().BoolVar(&flagRulesOnly, "rules-only", false, "Update detection rules only (brain must exist)")
	return cmd
}

func newMonitorForwardingCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "forwarding",
		Short: "Deploy EventBridge forwarding rules in the current spoke account",
		Long: `Creates 2 EventBridge forwarding rules that route decoy events to the hub bus.
Requires the spoke to be authorized on the hub bus first (run monitor authorize in hub).

Guard: must be run from a SPOKE account.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if cfg.Monitoring.EventBusARN == "" {
				return fmt.Errorf("hub event bus ARN not found in config. Run `mirage monitor deploy` from hub first")
			}

			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			if err := awsctx.RequireSpoke(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			spoke, err := cfg.GetSpoke(identity.AccountID)
			if err != nil {
				return fmt.Errorf("current account not found in spoke config")
			}

			color.New(color.Bold).Println("\n▶ Deploying EventBridge Forwarding Rules")
			
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}
			templatesDir := filepath.Join(repoRoot, "Mirage-cli", "templates", "monitoring")
			
			if err := monitor.DeployForwarding(ctx, cfg, spoke.Alias, templatesDir, GlobalDryRun); err != nil {
				return fmt.Errorf("failed to deploy forwarding rules: %w", err)
			}
			
			if !GlobalDryRun {
				spoke.ForwardingDeployed = true
				cfg.UpdateSpoke(*spoke)
				if err := config.Save(cfg); err != nil {
					color.Yellow("⚠ Failed to save config: %v", err)
				}
				color.Green("✓ Forwarding rules deployed successfully.")
			}
			return nil
		},
	}
}

func newMonitorAuthorizeCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "authorize <spoke-id>",
		Short: "Grant a spoke account permission to PutEvents on the hub bus",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()
			spokeID := args[0]

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if cfg.Monitoring.EventBusName == "" {
				return fmt.Errorf("hub event bus name not found in config. Run `mirage monitor deploy` from hub first")
			}

			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			if err := awsctx.RequireHub(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			color.New(color.Bold).Printf("\n▶ Authorizing Spoke %s on Hub EventBus %s\n", spokeID, cfg.Monitoring.EventBusName)
			
			if err := monitor.AuthorizeSpoke(ctx, awsCfg, cfg.Monitoring.EventBusName, spokeID); err != nil {
				return fmt.Errorf("failed to authorize spoke: %w", err)
			}
			
			// Update config
			spoke, err := cfg.GetSpoke(spokeID)
			if err == nil {
				spoke.AuthorizedOnBus = true
				cfg.UpdateSpoke(*spoke)
				_ = config.Save(cfg)
			}

			color.Green("✓ Spoke %s authorized to PutEvents on hub bus.", spokeID)
			return nil
		},
	}
}

func newMonitorSubscribeCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "subscribe <email>",
		Short: "Add an alert email subscriber to the SNS topic",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()
			email := args[0]

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if cfg.Monitoring.SNSTopicARN == "" {
				return fmt.Errorf("SNS topic ARN not found in config. Run `mirage monitor deploy` from hub first")
			}

			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			if err := awsctx.RequireHub(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			color.New(color.Bold).Printf("\n▶ Subscribing %s to SNS Topic\n", email)
			
			if err := monitor.SubscribeEmail(ctx, awsCfg, cfg.Monitoring.SNSTopicARN, email); err != nil {
				return fmt.Errorf("failed to subscribe email: %w", err)
			}
			
			cfg.Alerts.Emails = append(cfg.Alerts.Emails, email)
			_ = config.Save(cfg)

			color.Green("✓ Subscribed successfully. Please check inbox to confirm subscription.")
			return nil
		},
	}
}

func newMonitorStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show monitoring pipeline health (brain, rules, bus, SNS)",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load()
			if err != nil {
				return err
			}

			bold := color.New(color.Bold)
			cyan := color.New(color.FgCyan)

			bold.Println("\n▶ Monitoring Pipeline Status")
			fmt.Println(strings.Repeat("=", 60))

			// Hub Status
			fmt.Println("\n[ Hub Account ]")
			if cfg.Monitoring.EventBusARN != "" {
				cyan.Printf("  ✓ EventBus:   Deployed (%s)\n", cfg.Monitoring.EventBusName)
			} else {
				color.Red("  ✗ EventBus:   Not Deployed")
			}

			if cfg.Monitoring.BrainLambdaARN != "" {
				cyan.Printf("  ✓ Brain:      Deployed\n")
			} else {
				color.Red("  ✗ Brain:      Not Deployed")
			}

			if cfg.Monitoring.SNSTopicARN != "" {
				cyan.Printf("  ✓ SNS Topic:  Deployed\n")
			} else {
				color.Red("  ✗ SNS Topic:  Not Deployed")
			}

			// Subscriptions
			if len(cfg.Alerts.Emails) > 0 {
				fmt.Printf("\n  Alert Subscribers:\n")
				for _, email := range cfg.Alerts.Emails {
					fmt.Printf("    - %s\n", email)
				}
			} else {
				fmt.Println("\n  Alert Subscribers: None")
			}

			// Spoke Status
			fmt.Println("\n[ Spoke Accounts ]")
			for _, spoke := range cfg.Accounts.Spokes {
				fmt.Printf("  %s (%s):\n", spoke.Alias, spoke.ID)
				
				if spoke.AuthorizedOnBus {
					cyan.Printf("    ✓ Authorized on Hub Bus\n")
				} else {
					color.Yellow("    ⚠ Not Authorized on Hub Bus")
				}

				if spoke.ForwardingDeployed {
					cyan.Printf("    ✓ Forwarding Rules Deployed\n")
				} else {
					color.Yellow("    ⚠ Forwarding Rules Not Deployed")
				}
			}

			fmt.Println()
			return nil
		},
	}
}

func newMonitorDestroyCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "destroy",
		Short: "Tear down the monitoring pipeline (detection-rules first, then brain)",
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			if err := awsctx.RequireHub(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			color.New(color.Bold).Println("\n▶ Destroying Detection Rules")
			if err := monitor.DestroyRules(ctx, cfg, GlobalDryRun); err != nil {
				color.Red("  ✗ Failed to destroy rules: %v", err)
			} else if !GlobalDryRun {
				color.Green("  ✓ Detection rules destroyed.")
			}

			color.New(color.Bold).Println("\n▶ Destroying Brain Module")
			
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}
			templatesDir := filepath.Join(repoRoot, "Mirage-cli", "templates", "monitoring")
			
			if err := monitor.DestroyBrain(ctx, cfg, templatesDir, GlobalDryRun); err != nil {
				color.Red("  ✗ Failed to destroy brain: %v", err)
			} else if !GlobalDryRun {
				color.Green("  ✓ Brain module destroyed.")
			}
			
			if !GlobalDryRun {
				cfg.Monitoring.EventBusARN = ""
				cfg.Monitoring.SNSTopicARN = ""
				cfg.Monitoring.BrainLambdaARN = ""
				_ = config.Save(cfg)
			}

			return nil
		},
	}
}
