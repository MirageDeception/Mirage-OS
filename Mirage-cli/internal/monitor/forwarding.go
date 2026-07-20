package monitor

import (
	"context"
	"fmt"
	"path/filepath"

	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/tf"
)

func DeployForwarding(ctx context.Context, cfg *config.Config, spokeAlias string, templatesDir string, dryRun bool) error {
	runner := tf.NewRunner(true)

	if err := tf.CheckInstalled(); err != nil {
		return err
	}

	forwardingDir := filepath.Join(templatesDir, "forwarding")
	statePath := tf.StatePath(config.MirageDir(), "monitor", spokeAlias, "forwarding")

	if err := tf.EnsureStateDir(statePath); err != nil {
		return err
	}
	if err := tf.WriteBackendOverride(forwardingDir, statePath); err != nil {
		return err
	}
	defer tf.RemoveBackendOverride(forwardingDir)

	vars := map[string]string{
		"hub_event_bus_arn": cfg.Monitoring.EventBusARN,
		"rule_name":         fmt.Sprintf("mirage-forwarding-%s", spokeAlias),
	}

	_, err := runner.ApplyWithVars(ctx, forwardingDir, vars, dryRun)
	return err
}

func DestroyForwarding(ctx context.Context, cfg *config.Config, spokeAlias string, templatesDir string, dryRun bool) error {
	runner := tf.NewRunner(true)

	forwardingDir := filepath.Join(templatesDir, "forwarding")
	statePath := tf.StatePath(config.MirageDir(), "monitor", spokeAlias, "forwarding")

	if !tf.StateExists(statePath) {
		return nil
	}

	if err := tf.WriteBackendOverride(forwardingDir, statePath); err != nil {
		return err
	}
	defer tf.RemoveBackendOverride(forwardingDir)

	vars := map[string]string{
		"hub_event_bus_arn": cfg.Monitoring.EventBusARN,
		"rule_name":         fmt.Sprintf("mirage-forwarding-%s", spokeAlias),
	}

	_, err := runner.DestroyWithVars(ctx, forwardingDir, vars, dryRun)
	return err
}
