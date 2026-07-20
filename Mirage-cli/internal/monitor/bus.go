package monitor

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge"
)

func AuthorizeSpoke(ctx context.Context, awsCfg aws.Config, eventBusName, spokeAccountID string) error {
	client := eventbridge.NewFromConfig(awsCfg)

	_, err := client.PutPermission(ctx, &eventbridge.PutPermissionInput{
		Action:       aws.String("events:PutEvents"),
		Principal:    aws.String(spokeAccountID),
		StatementId:  aws.String(fmt.Sprintf("AllowSpoke-%s", spokeAccountID)),
		EventBusName: aws.String(eventBusName),
	})
	
	if err != nil {
		return fmt.Errorf("failed to authorize spoke account %s on bus %s: %w", spokeAccountID, eventBusName, err)
	}

	return nil
}
