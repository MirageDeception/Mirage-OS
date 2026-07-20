package monitor

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/mirage-security/mirage/internal/catalogue"
	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/discovery"
	"github.com/mirage-security/mirage/internal/tf"
	"github.com/mirage-security/mirage/pkg/models"
)

// DeployRules reads all active catalogue resources, generates dynamic EventBridge rules, and applies them.
func DeployRules(ctx context.Context, cfg *config.Config, store catalogue.Store, scanner *discovery.Scanner, dryRun bool) error {
	runner := tf.NewRunner(true)

	if err := tf.CheckInstalled(); err != nil {
		return err
	}

	resources, err := store.ListResources(ctx, catalogue.ResourceFilter{Status: "active"})
	if err != nil {
		return fmt.Errorf("list resources: %w", err)
	}
	
	// Create a temporary dir for dynamic terraform rules
	rulesDir := filepath.Join(config.MirageDir(), "templates", "monitoring", "detection-rules")
	if err := os.MkdirAll(rulesDir, 0755); err != nil {
		return err
	}
	
	mainTfPath := filepath.Join(rulesDir, "main.tf")
	
	// Generate terraform content
	tfContent := `
variable "event_bus_name" { type = string }
variable "brain_lambda_arn" { type = string }

data "aws_cloudwatch_event_bus" "hub_bus" {
  name = var.event_bus_name
}
`
	
	// Group resources by Scenario
	scenarios := make(map[int][]models.Resource)
	for _, r := range resources {
		scenarios[r.ScenarioNum] = append(scenarios[r.ScenarioNum], r)
	}

	for scenarioNum, resList := range scenarios {
		manifest, err := scanner.GetScenario(scenarioNum)
		if err != nil {
			continue // skip missing scenario
		}
		
		for i, event := range manifest.Detection.Events {
			ruleName := fmt.Sprintf("mirage-rule-s%d-e%d", scenarioNum, i)
			
			// Build event pattern
			pattern := map[string]interface{}{
				"source": []string{event.Source},
			}
			
			if event.DetailType != "" {
				pattern["detail-type"] = []string{event.DetailType}
			}
			
			detail := map[string]interface{}{}
			if len(event.APICalls) > 0 {
				detail["eventName"] = event.APICalls
			}
			
			// Add resource ARN filtering if applicable
			var requestParams map[string]interface{}
			for _, r := range resList {
				// Depending on the service, ARNs or names are embedded in requestParameters
				// For now, this is a simplified stub. In a real scenario, this would be highly service-specific.
				if requestParams == nil {
					requestParams = make(map[string]interface{})
				}
				// e.g. for S3, bucketName
				requestParams["bucketName"] = []string{r.ResourceName}
			}
			
			if len(requestParams) > 0 {
				detail["requestParameters"] = requestParams
			}
			
			pattern["detail"] = detail
			
			patternBytes, _ := json.Marshal(pattern)
			
			tfContent += fmt.Sprintf(`
resource "aws_cloudwatch_event_rule" "%s" {
  name        = "%s"
  description = "Detection rule for Scenario %d"
  event_bus_name = data.aws_cloudwatch_event_bus.hub_bus.name
  
  event_pattern = %s
}

resource "aws_cloudwatch_event_target" "%s_target" {
  rule           = aws_cloudwatch_event_rule.%s.name
  event_bus_name = data.aws_cloudwatch_event_bus.hub_bus.name
  target_id      = "MirageBrain"
  arn            = var.brain_lambda_arn
}
`, ruleName, ruleName, scenarioNum, string(patternBytes), ruleName, ruleName)
		}
	}
	
	if err := os.WriteFile(mainTfPath, []byte(tfContent), 0644); err != nil {
		return err
	}
	
	statePath := tf.StatePath(config.MirageDir(), "monitor", "hub", "rules")
	if err := tf.EnsureStateDir(statePath); err != nil {
		return err
	}
	if err := tf.WriteBackendOverride(rulesDir, statePath); err != nil {
		return err
	}
	defer tf.RemoveBackendOverride(rulesDir)
	
	vars := map[string]string{
		"event_bus_name":   cfg.Monitoring.EventBusName,
		"brain_lambda_arn": cfg.Monitoring.BrainLambdaARN,
	}
	
	_, err = runner.ApplyWithVars(ctx, rulesDir, vars, dryRun)
	return err
}

func DestroyRules(ctx context.Context, cfg *config.Config, dryRun bool) error {
	runner := tf.NewRunner(true)

	rulesDir := filepath.Join(config.MirageDir(), "templates", "monitoring", "detection-rules")
	statePath := tf.StatePath(config.MirageDir(), "monitor", "hub", "rules")
	
	if !tf.StateExists(statePath) {
		return nil
	}
	
	if err := tf.WriteBackendOverride(rulesDir, statePath); err != nil {
		return err
	}
	defer tf.RemoveBackendOverride(rulesDir)
	
	vars := map[string]string{
		"event_bus_name":   cfg.Monitoring.EventBusName,
		"brain_lambda_arn": cfg.Monitoring.BrainLambdaARN, // Will use state if not in config
	}
	
	_, err := runner.DestroyWithVars(ctx, rulesDir, vars, dryRun)
	return err
}
