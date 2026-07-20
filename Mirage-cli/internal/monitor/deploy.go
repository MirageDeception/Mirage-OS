package monitor

import (
	"context"
	"path/filepath"

	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/tf"
)

func DeployBrain(ctx context.Context, cfg *config.Config, templatesDir string, dryRun bool) (map[string]string, error) {
	runner := tf.NewRunner(true)

	if err := tf.CheckInstalled(); err != nil {
		return nil, err
	}

	brainDir := filepath.Join(templatesDir, "brain")
	statePath := tf.StatePath(config.MirageDir(), "monitor", "hub", "brain")

	if err := tf.EnsureStateDir(statePath); err != nil {
		return nil, err
	}
	if err := tf.WriteBackendOverride(brainDir, statePath); err != nil {
		return nil, err
	}
	defer tf.RemoveBackendOverride(brainDir)

	vars := map[string]string{
		"event_bus_name":       cfg.Monitoring.EventBusName,
		"sns_topic_name":       "mirage-deception-alerts",
		"lambda_function_name": "mirage-brain",
	}

	res, err := runner.ApplyWithVars(ctx, brainDir, vars, dryRun)
	if err != nil {
		return nil, err
	}

	return res.Outputs, nil
}

func DestroyBrain(ctx context.Context, cfg *config.Config, templatesDir string, dryRun bool) error {
	runner := tf.NewRunner(true)

	if err := tf.CheckInstalled(); err != nil {
		return err
	}

	brainDir := filepath.Join(templatesDir, "brain")
	statePath := tf.StatePath(config.MirageDir(), "monitor", "hub", "brain")

	if !tf.StateExists(statePath) {
		return nil
	}

	if err := tf.WriteBackendOverride(brainDir, statePath); err != nil {
		return err
	}
	defer tf.RemoveBackendOverride(brainDir)

	vars := map[string]string{
		"event_bus_name":       cfg.Monitoring.EventBusName,
		"sns_topic_name":       "mirage-deception-alerts",
		"lambda_function_name": "mirage-brain",
	}

	_, err := runner.DestroyWithVars(ctx, brainDir, vars, dryRun)
	return err
}
