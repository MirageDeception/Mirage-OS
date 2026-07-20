package verify

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"
)

// SendNotification sends an SNS message during the drill.
func SendNotification(ctx context.Context, cfg DrillConfig, message string) error {
	if cfg.SNSTopicARN == "" {
		return fmt.Errorf("SNS Topic ARN not configured")
	}

	client := sns.NewFromConfig(cfg.AWSConfig)
	
	_, err := client.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(cfg.SNSTopicARN),
		Subject:  aws.String("Mirage Drill Notification"),
		Message:  aws.String(message),
	})
	
	if err != nil {
		return fmt.Errorf("failed to publish drill notification: %w", err)
	}

	return nil
}
