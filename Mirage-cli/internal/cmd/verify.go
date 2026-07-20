package cmd

import (
	"context"
	"fmt"

	"github.com/mirage-security/mirage/internal/awsctx"
	"github.com/mirage-security/mirage/internal/catalogue"
	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/verify"
	"github.com/spf13/cobra"
)

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
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if cfg.Monitoring.EventBusName == "" {
				return fmt.Errorf("hub event bus not configured. run 'mirage monitor deploy' first")
			}

			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			if err := awsctx.RequireHub(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			store, err := catalogue.NewSQLiteStore(cfg.Catalogue.SQLitePath)
			if err != nil {
				return fmt.Errorf("open catalogue: %w", err)
			}
			defer store.Close()

			awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}

			return verify.RunDrill(ctx, verify.DrillConfig{
				AWSConfig:       awsCfg,
				EventBusName:    cfg.Monitoring.EventBusName,
				BrainLambdaName: "mirage-brain", // deployed by monitor
				SNSTopicARN:     cfg.Monitoring.SNSTopicARN,
				Catalogue:       store,
				TemplatesPath:   cfg.Templates.Local.Path,
				TargetScenario:  flagScenario,
				TimeoutSecs:     flagTimeout,
				Notify:          flagDrillNotify,
				Identity:        identity,
			})
		},
	}
	cmd.Flags().IntVar(&flagScenario, "scenario", 0, "Target specific scenario (default: random from catalogue)")
	cmd.Flags().IntVar(&flagTimeout, "timeout", 30, "Seconds to wait for Lambda invocation")
	cmd.Flags().BoolVar(&flagDrillNotify, "drill-notify", false, "Send SNS pre/post drill notifications to subscribers")
	return cmd
}
