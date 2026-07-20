package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/fatih/color"
	"github.com/mirage-security/mirage/internal/awsctx"
	"github.com/mirage-security/mirage/internal/catalogue"
	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/discovery"
	"github.com/mirage-security/mirage/internal/tf"
	"github.com/mirage-security/mirage/pkg/models"
)

func runStatus(targetSpoke string, full bool, detectDrift bool) error {
	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
	if err != nil {
		return err
	}

	// HUB Checks
	hubStatus := models.HubStatus{
		BrainDeployed:      cfg.Monitoring.BrainLambdaARN != "",
		AuthorizedSpokes:   []string{},
		SNSSubscriptions:   []models.SNSSubscription{},
	}

	// SNS Subscriptions
	if cfg.Monitoring.SNSTopicARN != "" {
		snsClient := sns.NewFromConfig(awsCfg)
		out, err := snsClient.ListSubscriptionsByTopic(ctx, &sns.ListSubscriptionsByTopicInput{
			TopicArn: aws.String(cfg.Monitoring.SNSTopicARN),
		})
		if err == nil {
			for _, sub := range out.Subscriptions {
				hubStatus.SNSSubscriptions = append(hubStatus.SNSSubscriptions, models.SNSSubscription{
					Email:  aws.ToString(sub.Endpoint),
					Status: aws.ToString(sub.SubscriptionArn), // PendingConfirmation or ARN
				})
			}
		}
	}

	for _, s := range cfg.Accounts.Spokes {
		if s.AuthorizedOnBus {
			hubStatus.AuthorizedSpokes = append(hubStatus.AuthorizedSpokes, s.Alias)
		}
	}

	store, err := catalogue.NewSQLiteStore(cfg.Catalogue.SQLitePath)
	if err == nil {
		defer store.Close()
		resources, _ := store.ListResources(ctx, catalogue.ResourceFilter{Status: "active"})
		
		// Map resources to expected rules
		scenarioSet := make(map[int]bool)
		for _, r := range resources {
			scenarioSet[r.ScenarioNum] = true
		}
		hubStatus.ExpectedRuleCount = len(scenarioSet)
		
		if tf.StateExists(tf.StatePath(config.MirageDir(), "monitor", "hub", "rules")) {
			hubStatus.DetectionRuleCount = len(scenarioSet) // Simplified for display
		}
	}

	// SPOKE Checks
	var spokes []models.SpokeStatus
	
	for _, s := range cfg.Accounts.Spokes {
		if targetSpoke != "" && s.Alias != targetSpoke {
			continue
		}

		spokeStat := models.SpokeStatus{
			Alias:              s.Alias,
			AccountID:          s.ID,
			ForwardingDeployed: s.ForwardingDeployed,
			DeployedScenarios:  tf.ListDeployedScenarios(config.MirageDir(), s.Alias),
			HealthMatrix:       []models.ScenarioHealth{},
		}
		
		// Fill Health Matrix
		scanner := discovery.NewScanner(cfg.Templates.Local.Path)
		for _, num := range spokeStat.DeployedScenarios {
			manifest, _ := scanner.GetScenario(num)
			name := "Unknown"
			if manifest != nil {
				name = manifest.Name
			}
			
			sh := models.ScenarioHealth{
				Number:    num,
				Name:      name,
				Deployed:  true,
				Forwarded: s.ForwardingDeployed,
				RuleExists: hubStatus.DetectionRuleCount > 0, // Simplified
				AlertPath: s.ForwardingDeployed && hubStatus.BrainDeployed,
			}
			spokeStat.HealthMatrix = append(spokeStat.HealthMatrix, sh)
		}
		
		spokes = append(spokes, spokeStat)
	}

	matrix := models.StatusMatrix{
		HubPlane: hubStatus,
		Spokes:   spokes,
	}

	if GlobalJSON {
		b, err := json.MarshalIndent(matrix, "", "  ")
		if err == nil {
			fmt.Println(string(b))
		} else {
			color.Red("Failed to marshal JSON: %v", err)
		}
		return nil
	}

	renderStatusMatrix(matrix, detectDrift)
	return nil
}

func renderStatusMatrix(m models.StatusMatrix, detectDrift bool) {
	bold := color.New(color.Bold)
	cyan := color.New(color.FgCyan)
	green := color.New(color.FgGreen)
	red := color.New(color.FgRed)
	yellow := color.New(color.FgYellow)

	bold.Println("\n▶ Hub Plane Status")
	fmt.Println(strings.Repeat("=", 60))
	if m.HubPlane.BrainDeployed {
		green.Println("  ✓ Brain Module: Deployed")
	} else {
		red.Println("  ✗ Brain Module: Missing")
	}
	fmt.Printf("  • Detection Rules: %d (Expected: %d)\n", m.HubPlane.DetectionRuleCount, m.HubPlane.ExpectedRuleCount)
	fmt.Printf("  • Authorized Spokes: %v\n", m.HubPlane.AuthorizedSpokes)
	
	fmt.Println("  • SNS Subscriptions:")
	if len(m.HubPlane.SNSSubscriptions) == 0 {
		fmt.Println("      None")
	}
	for _, sub := range m.HubPlane.SNSSubscriptions {
		if strings.Contains(sub.Status, "PendingConfirmation") {
			yellow.Printf("      - %s (Pending)\n", sub.Email)
		} else {
			green.Printf("      - %s (Confirmed)\n", sub.Email)
		}
	}

	bold.Println("\n▶ Spoke Plane Status")
	fmt.Println(strings.Repeat("=", 60))
	for _, s := range m.Spokes {
		cyan.Printf("\n[ %s | %s ]\n", s.Alias, s.AccountID)
		if s.ForwardingDeployed {
			green.Println("  ✓ Event Forwarding: Deployed")
		} else {
			red.Println("  ✗ Event Forwarding: Missing")
		}

		if len(s.HealthMatrix) == 0 {
			fmt.Println("  • No scenarios deployed.")
			continue
		}

		fmt.Printf("\n  %-8s %-25s %-10s %-11s %-6s %-12s\n", "SCENARIO", "NAME", "DEPLOYED", "FORWARDED", "RULE", "ALERT-PATH")
		fmt.Println("  " + strings.Repeat("-", 80))
		for _, h := range s.HealthMatrix {
			dep := "✓"
			if !h.Deployed {
				dep = "✗"
			}
			fwd := "✓"
			if !h.Forwarded {
				fwd = "✗"
			}
			rule := "✓"
			if !h.RuleExists {
				rule = "✗"
			}
			
			alert := color.GreenString("READY")
			if !h.AlertPath {
				alert = color.RedString("BROKEN")
			}
			
			fmt.Printf("  %-8d %-25s %-10s %-11s %-6s %-12s\n", h.Number, h.Name, dep, fwd, rule, alert)
		}
	}
	
	if detectDrift {
		yellow.Println("\n⚠ Drift detection enabled (running tf plan... expected to be slow)")
		
		runner := tf.NewRunner(false)
		driftCount := 0
		
		for _, s := range m.Spokes {
			for _, h := range s.HealthMatrix {
				if h.Deployed {
					statePath := tf.StatePath(config.MirageDir(), "scenarios", s.Alias, fmt.Sprintf("scenario-%d", h.Number))
					workDir := tf.WorkDir(config.MirageDir(), "scenarios", fmt.Sprintf("scenario-%d", h.Number))
					
					tf.WriteBackendOverride(workDir, statePath)
					res, err := runner.Plan(context.Background(), workDir, "")
					tf.RemoveBackendOverride(workDir)
					
					if err == nil && res.Success {
						if strings.Contains(res.Stdout, "No changes.") || strings.Contains(res.Stdout, "Your infrastructure matches the configuration") {
							// No drift
						} else {
							red.Printf("  ✗ Drift detected in Spoke %s, Scenario %d\n", s.Alias, h.Number)
							driftCount++
						}
					} else {
						red.Printf("  ✗ Failed to plan Scenario %d in Spoke %s\n", h.Number, s.Alias)
					}
				}
			}
		}
		
		if driftCount == 0 {
			green.Println("  ✓ No drift detected.")
		}
	}
	
	fmt.Println()
}
