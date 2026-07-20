package monitor

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sns"
)

func SubscribeEmail(ctx context.Context, awsCfg aws.Config, topicArn, email string) error {
	client := sns.NewFromConfig(awsCfg)

	_, err := client.Subscribe(ctx, &sns.SubscribeInput{
		Protocol:              aws.String("email"),
		TopicArn:              aws.String(topicArn),
		Endpoint:              aws.String(email),
		ReturnSubscriptionArn: true,
	})
	
	if err != nil {
		return fmt.Errorf("failed to subscribe %s to topic %s: %w", email, topicArn, err)
	}

	return nil
}
