package verify

import (
	"context"
	"fmt"
	"math/rand"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/fatih/color"
	"github.com/mirage-security/mirage/internal/catalogue"
	"github.com/mirage-security/mirage/pkg/models"
)

type DrillConfig struct {
	AWSConfig       aws.Config
	EventBusName    string
	BrainLambdaName string
	SNSTopicARN     string
	Catalogue       catalogue.Store
	TemplatesPath   string
	TargetScenario  int
	TimeoutSecs     int
	Notify          bool
	Identity        *models.Identity
}

func RunDrill(ctx context.Context, cfg DrillConfig) error {
	color.New(color.Bold).Println("\n▶ Initiating Synthetic Drill")
	
	resources, err := cfg.Catalogue.ListResources(ctx, catalogue.ResourceFilter{Status: "active"})
	if err != nil {
		return fmt.Errorf("failed to list deployed resources: %w", err)
	}

	if len(resources) == 0 {
		return fmt.Errorf("no active deception resources found in catalogue. deploy scenarios first")
	}

	var targetResource models.Resource
	if cfg.TargetScenario > 0 {
		found := false
		for _, r := range resources {
			if r.ScenarioNum == cfg.TargetScenario {
				targetResource = r
				found = true
				break
			}
		}
		if !found {
			return fmt.Errorf("scenario %d is not currently deployed", cfg.TargetScenario)
		}
	} else {
		// Pick random
		targetResource = resources[rand.Intn(len(resources))]
	}

	color.Cyan("  • Target Scenario: %d (%s)", targetResource.ScenarioNum, targetResource.ScenarioName)
	color.Cyan("  • Target Spoke:    %s", targetResource.SpokeAlias)
	color.Cyan("  • Target Resource: %s", targetResource.ResourceName)

	if cfg.Notify {
		color.Yellow("  • Sending pre-drill SNS notification...")
		_ = SendNotification(ctx, cfg, fmt.Sprintf("⚠️ DRILL: Mirage verification in progress for scenario %d. Next alert is a test.", targetResource.ScenarioNum))
	}

	drillID, err := InjectDrillEvent(ctx, cfg, targetResource)
	if err != nil {
		return fmt.Errorf("failed to inject drill event: %w", err)
	}

	color.Cyan("  • Injected synthetic EventBridge payload (Drill ID: %s)", drillID)
	color.Yellow("  • Polling CloudWatch Logs for Brain Lambda invocation (timeout: %ds)...", cfg.TimeoutSecs)

	startTime := time.Now()
	success := PollForInvocation(ctx, cfg, drillID, startTime)

	latency := time.Since(startTime)

	if success {
		color.Green("\n  ✓ PASS: Drill event detected by Brain Lambda in %v", latency)
		_ = cfg.Catalogue.SetLastVerified(ctx, targetResource.ID, time.Now())
	} else {
		color.Red("\n  ✗ FAIL: Drill event not detected within timeout")
	}

	if cfg.Notify {
		statusStr := "PASS"
		if !success {
			statusStr = "FAIL"
		}
		_ = SendNotification(ctx, cfg, fmt.Sprintf("Drill complete for scenario %d: %s (Latency: %v)", targetResource.ScenarioNum, statusStr, latency))
	}

	// Audit Log
	_ = cfg.Catalogue.LogOperation(ctx, models.Operation{
		Timestamp:   time.Now(),
		Operator:    cfg.Identity.ARN,
		Command:     fmt.Sprintf("verify --scenario %d", targetResource.ScenarioNum),
		AccountID:   cfg.Identity.AccountID,
		SpokeAlias:  targetResource.SpokeAlias,
		ScenarioNum: targetResource.ScenarioNum,
	})

	if !success {
		return fmt.Errorf("drill failed: alert path broken")
	}
	return nil
}
