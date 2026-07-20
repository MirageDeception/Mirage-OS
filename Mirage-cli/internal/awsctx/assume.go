package awsctx

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sts"
)

// AssumeRole returns temporary credentials for the target role.
func AssumeRole(ctx context.Context, region, profile, roleARN, sessionName, externalID string) (aws.Credentials, error) {
	cfg, err := loadAWSConfig(ctx, region, profile)
	if err != nil {
		return aws.Credentials{}, err
	}

	client := sts.NewFromConfig(cfg)
	
	input := &sts.AssumeRoleInput{
		RoleArn:         aws.String(roleARN),
		RoleSessionName: aws.String(sessionName),
		DurationSeconds: aws.Int32(900), // 15 mins minimum
	}
	
	if externalID != "" {
		input.ExternalId = aws.String(externalID)
	}

	out, err := client.AssumeRole(ctx, input)
	if err != nil {
		return aws.Credentials{}, fmt.Errorf("assume role %s: %w", roleARN, err)
	}

	if out.Credentials == nil {
		return aws.Credentials{}, fmt.Errorf("no credentials returned for role %s", roleARN)
	}

	return aws.Credentials{
		AccessKeyID:     *out.Credentials.AccessKeyId,
		SecretAccessKey: *out.Credentials.SecretAccessKey,
		SessionToken:    *out.Credentials.SessionToken,
	}, nil
}
