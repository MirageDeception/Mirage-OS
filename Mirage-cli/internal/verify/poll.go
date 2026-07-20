package verify

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
)

// PollForInvocation checks CloudWatch logs for a specific drill_id
func PollForInvocation(ctx context.Context, cfg DrillConfig, drillID string, startTime time.Time) bool {
	client := cloudwatchlogs.NewFromConfig(cfg.AWSConfig)
	logGroupName := fmt.Sprintf("/aws/lambda/%s", cfg.BrainLambdaName)

	timeout := time.After(time.Duration(cfg.TimeoutSecs) * time.Second)
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	startTimeMs := startTime.UnixNano() / int64(time.Millisecond)

	for {
		select {
		case <-ctx.Done():
			return false
		case <-timeout:
			return false
		case <-ticker.C:
			// Query logs
			out, err := client.FilterLogEvents(ctx, &cloudwatchlogs.FilterLogEventsInput{
				LogGroupName: aws.String(logGroupName),
				StartTime:    aws.Int64(startTimeMs),
				FilterPattern: aws.String(fmt.Sprintf("{ $.mirage_drill = true || %q }", drillID)),
			})

			// If the log group doesn't exist yet (e.g. lambda never invoked), ignore the error
			if err != nil {
				if strings.Contains(err.Error(), "ResourceNotFoundException") {
					continue
				}
				// Other errors: we just continue polling, maybe print debug in verbose mode
				continue
			}

			for _, event := range out.Events {
				if strings.Contains(aws.ToString(event.Message), drillID) {
					return true
				}
			}
		}
	}
}
