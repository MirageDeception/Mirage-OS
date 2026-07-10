// Package cmd contains all Cobra command handlers.
// Commands are thin — they parse flags and delegate to internal packages.
package cmd

import (
	"fmt"
	"os"

	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

// Global flag values shared by all commands.
var (
	GlobalRegion  string
	GlobalProfile string
	GlobalYes     bool
	GlobalDryRun  bool
	GlobalJSON    bool
	GlobalVerbose bool
)

var rootCmd = &cobra.Command{
	Use:   "mirage",
	Short: "Cloud Deception Infrastructure CLI",
	Long: color.New(color.FgCyan, color.Bold).Sprint(`
  ███╗   ███╗██╗██████╗  █████╗  ██████╗ ███████╗
  ████╗ ████║██║██╔══██╗██╔══██╗██╔════╝ ██╔════╝
  ██╔████╔██║██║██████╔╝███████║██║  ███╗█████╗
  ██║╚██╔╝██║██║██╔══██╗██╔══██║██║   ██║██╔══╝
  ██║ ╚═╝ ██║██║██║  ██║██║  ██║╚██████╔╝███████╗
  ╚═╝     ╚═╝╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
`) + `
  Cloud Deception Infrastructure — Hub/Spoke Model
  Deploy honeypots, lures, and decoys across AWS accounts.
  Every interaction with a decoy resource is a confirmed true positive.

  Quick start:
    mirage init                          bootstrap config
    mirage roles deploy --all-spokes     deploy cross-account IAM roles
    mirage monitor deploy                deploy detection pipeline (hub)
    mirage monitor forwarding            deploy event forwarding (spoke)
    mirage scenario deploy --all         deploy all 19 deception scenarios

  Docs: https://github.com/mirage-security/mirage`,
	SilenceErrors: true,
	SilenceUsage:  true,
}

// Execute is the binary entry point.
func Execute() error {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, color.RedString("Error: ")+err.Error())
		return err
	}
	return nil
}

func init() {
	rootCmd.PersistentFlags().StringVar(&GlobalRegion, "region", "", "AWS region (default: us-west-2 or config value)")
	rootCmd.PersistentFlags().StringVar(&GlobalProfile, "profile", "", "AWS named profile (overrides AWS_PROFILE env var)")
	rootCmd.PersistentFlags().BoolVarP(&GlobalYes, "yes", "y", false, "Skip confirmation prompts (except double-confirm on destructive commands)")
	rootCmd.PersistentFlags().BoolVar(&GlobalDryRun, "dry-run", false, "Show what would happen without making changes")
	rootCmd.PersistentFlags().BoolVar(&GlobalJSON, "json", false, "Output machine-readable JSON")
	rootCmd.PersistentFlags().BoolVarP(&GlobalVerbose, "verbose", "v", false, "Enable verbose/debug output")

	// Register subcommand groups.
	rootCmd.AddCommand(newInitCmd())
	rootCmd.AddCommand(newConfigCmd())
	rootCmd.AddCommand(newRolesCmd())
	rootCmd.AddCommand(newScenarioCmd())
	rootCmd.AddCommand(newMonitorCmd())
	rootCmd.AddCommand(newStatusCmd())
	rootCmd.AddCommand(newVerifyCmd())
	rootCmd.AddCommand(newCatalogueCmd())
	rootCmd.AddCommand(newVersionCmd())
}
