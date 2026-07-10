package cmd

import (
	"github.com/fatih/color"
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
			color.Yellow("⚠ Phase 6 feature: scenario list — not yet implemented.")
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
			color.Yellow("⚠ Phase 6 feature: scenario show — not yet implemented.")
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
			color.Yellow("⚠ Phase 6 feature: scenario deploy — not yet implemented.")
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
			color.Yellow("⚠ Phase 6 feature: scenario destroy — not yet implemented.")
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
			// Safety check: reject --all explicitly.
			color.Yellow("⚠ Phase 10 feature: scenario abuse — not yet implemented.")
			return nil
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
			color.Yellow("⚠ Phase 6 feature: scenario status — not yet implemented.")
			return nil
		},
	}
}
