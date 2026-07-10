package cmd

import (
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

func newStatusCmd() *cobra.Command {
	var (
		flagSpoke string
		flagFull  bool
	)
	cmd := &cobra.Command{
		Use:   "status",
		Short: "Show end-to-end deception posture across all planes",
		Long: `Reconciles config → catalogue → live AWS state.

Checks:
  HUB PLANE:
    • Brain module deployed (EventBus + Lambda + SNS)
    • Detection rules: count vs expected
    • Spoke authorizations
    • SNS subscription status

  SPOKE PLANE (per spoke):
    • Forwarding rules deployed and ENABLED
    • Scenario deployment count
    • Catalogue consistency

  MATRIX (per scenario per spoke):
    deployed | forwarded | rule | alert-path | last-verified

Use --json for CI integration.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			color.Yellow("⚠ Phase 8 feature: status — not yet implemented.")
			return nil
		},
	}
	cmd.Flags().StringVar(&flagSpoke, "spoke", "", "Show status for single spoke only")
	cmd.Flags().BoolVar(&flagFull, "full", false, "Include ARN-level detail for each resource")
	return cmd
}

func newVerifyCmd() *cobra.Command {
	var (
		flagScenario    int
		flagTimeout     int
		flagDrillNotify bool
	)
	cmd := &cobra.Command{
		Use:   "verify",
		Short: "Inject a synthetic drill event and verify the alert path fires",
		Long: `Proves the detection pipeline works end-to-end:
  1. Inject synthetic CloudTrail-shaped event (tagged as drill)
  2. Poll CloudWatch for Lambda invocation
  3. Measure latency (target: 8–12 seconds)
  4. Report PASS/FAIL + latency
  5. Update catalogue with last_verified timestamp

This is SAFE — events are tagged with mirage_drill=true.
Use scenario abuse <n> for real attacker simulation.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			color.Yellow("⚠ Phase 9 feature: verify — not yet implemented.")
			return nil
		},
	}
	cmd.Flags().IntVar(&flagScenario, "scenario", 0, "Target specific scenario (default: random from catalogue)")
	cmd.Flags().IntVar(&flagTimeout, "timeout", 30, "Seconds to wait for Lambda invocation")
	cmd.Flags().BoolVar(&flagDrillNotify, "drill-notify", false, "Send SNS pre/post drill notifications to subscribers")
	return cmd
}

func newCatalogueCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "catalogue",
		Short: "View and manage the deployed resource registry",
	}

	cmd.AddCommand(&cobra.Command{
		Use:   "show",
		Short: "List all tracked resources in the catalogue",
		RunE: func(cmd *cobra.Command, args []string) error {
			color.Yellow("⚠ Phase 4 feature: catalogue show — not yet implemented.")
			return nil
		},
	})

	cmd.AddCommand(&cobra.Command{
		Use:   "sync",
		Short: "Reconcile catalogue against terraform state and live AWS",
		RunE: func(cmd *cobra.Command, args []string) error {
			color.Yellow("⚠ Phase 4 feature: catalogue sync — not yet implemented.")
			return nil
		},
	})

	cmd.AddCommand(&cobra.Command{
		Use:   "export",
		Short: "Export catalogue to JSON or CSV for audit",
		RunE: func(cmd *cobra.Command, args []string) error {
			color.Yellow("⚠ Phase 4 feature: catalogue export — not yet implemented.")
			return nil
		},
	})

	return cmd
}

func newVersionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version information",
		Run: func(cmd *cobra.Command, args []string) {
			// Values injected via ldflags at build time.
			color.Cyan("mirage version %s (commit: %s, built: %s)\n", Version, Commit, BuildDate)
		},
	}
}

// Build-time variables injected via ldflags.
// go build -ldflags "-X github.com/mirage-security/mirage/internal/cmd.Version=1.0.0"
var (
	Version   = "dev"
	Commit    = "none"
	BuildDate = "unknown"
)
