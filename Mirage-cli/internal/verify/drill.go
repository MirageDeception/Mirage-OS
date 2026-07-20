package verify

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge/types"
	"github.com/google/uuid"
	"github.com/mirage-security/mirage/internal/discovery"
	"github.com/mirage-security/mirage/pkg/models"
)

// InjectDrillEvent parses the scenario manifest, generates a matching CloudTrail event,
// injects a mirage_drill=true tag, and puts it onto the EventBus.
func InjectDrillEvent(ctx context.Context, cfg DrillConfig, target models.Resource) (string, error) {
	scanner := discovery.NewScanner(cfg.TemplatesPath)
	manifest, err := scanner.GetScenario(target.ScenarioNum)
	if err != nil {
		return "", fmt.Errorf("read scenario manifest: %w", err)
	}

	if len(manifest.Detection.Events) == 0 {
		return "", fmt.Errorf("no detection events defined in scenario %d", target.ScenarioNum)
	}

	// Pick the first event signature to mock
	sig := manifest.Detection.Events[0]
	
	drillID := uuid.New().String()

	detail := map[string]interface{}{
		"mirage_drill": true,
		"drill_id":     drillID,
	}

	if len(sig.APICalls) > 0 {
		detail["eventName"] = sig.APICalls[0] // just pick the first API call
	}

	// For simple matching, inject the resource name into requestParameters (matches how rules.go builds it)
	// Some services might look at requestParameters.bucketName, etc. We just put it generically if needed,
	// but rules.go specifically does `requestParameters.bucketName` for S3.
	// To be robust, let's just dump it into a few common spots the rule might look.
	detail["requestParameters"] = map[string]interface{}{
		"bucketName":   target.ResourceName,
		"userName":     target.ResourceName,
		"resourceName": target.ResourceName,
	}

	detailBytes, _ := json.Marshal(detail)

	detailType := sig.DetailType
	if detailType == "" {
		detailType = "AWS API Call via CloudTrail" // standard CloudTrail detail type
	}

	client := eventbridge.NewFromConfig(cfg.AWSConfig)
	
	_, err = client.PutEvents(ctx, &eventbridge.PutEventsInput{
		Entries: []types.PutEventsRequestEntry{
			{
				EventBusName: aws.String(cfg.EventBusName),
				Source:       aws.String(sig.Source),
				DetailType:   aws.String(detailType),
				Detail:       aws.String(string(detailBytes)),
				Time:         aws.Time(time.Now()),
			},
		},
	})

	if err != nil {
		return "", fmt.Errorf("PutEvents failed: %w", err)
	}

	return drillID, nil
}
