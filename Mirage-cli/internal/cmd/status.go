package cmd

import (
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

func newStatusCmd() *cobra.Command {
	var (
		flagSpoke       string
		flagFull        bool
		flagDetectDrift bool
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
			return runStatus(flagSpoke, flagFull, flagDetectDrift)
		},
	}
	cmd.Flags().StringVar(&flagSpoke, "spoke", "", "Show status for single spoke only")
	cmd.Flags().BoolVar(&flagFull, "full", false, "Include ARN-level detail for each resource")
	cmd.Flags().BoolVar(&flagDetectDrift, "detect-drift", false, "Run slow drift detection (terraform plan) on all deployed modules")
	return cmd
}


// newCatalogueCmd is implemented in catalogue.go

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
