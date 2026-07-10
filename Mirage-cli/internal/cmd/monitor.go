package cmd

import (
	"github.com/fatih/color"
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
			color.Yellow("⚠ Phase 7 feature: monitor deploy — not yet implemented.")
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
			color.Yellow("⚠ Phase 7 feature: monitor forwarding — not yet implemented.")
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
			color.Yellow("⚠ Phase 7 feature: monitor authorize — not yet implemented.")
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
			color.Yellow("⚠ Phase 7 feature: monitor subscribe — not yet implemented.")
			return nil
		},
	}
}

func newMonitorStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show monitoring pipeline health (brain, rules, bus, SNS)",
		RunE: func(cmd *cobra.Command, args []string) error {
			color.Yellow("⚠ Phase 7 feature: monitor status — not yet implemented.")
			return nil
		},
	}
}

func newMonitorDestroyCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "destroy",
		Short: "Tear down the monitoring pipeline (detection-rules first, then brain)",
		RunE: func(cmd *cobra.Command, args []string) error {
			color.Yellow("⚠ Phase 7 feature: monitor destroy — not yet implemented.")
			return nil
		},
	}
}
