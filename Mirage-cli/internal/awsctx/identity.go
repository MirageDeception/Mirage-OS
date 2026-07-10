// Package awsctx resolves and validates the current AWS identity.
package awsctx

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/mirage-security/mirage/pkg/models"
)

// STSClient is an interface over the STS operations mirage uses.
// Implemented by the real AWS STS client and a mock in tests.
type STSClient interface {
	GetCallerIdentity(ctx context.Context, params *sts.GetCallerIdentityInput, optFns ...func(*sts.Options)) (*sts.GetCallerIdentityOutput, error)
}

// GetIdentity calls sts:GetCallerIdentity and returns the current AWS identity.
// Uses the profile/region from global CLI flags if provided.
func GetIdentity(ctx context.Context, region, profile string) (*models.Identity, error) {
	cfg, err := loadAWSConfig(ctx, region, profile)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w\n\nFix: configure credentials via 'aws configure' or set AWS_PROFILE env var", err)
	}
	client := sts.NewFromConfig(cfg)
	return getIdentityFromClient(ctx, client)
}

// GetIdentityWithClient calls sts:GetCallerIdentity using a provided STS client (for testing).
func GetIdentityWithClient(ctx context.Context, client STSClient) (*models.Identity, error) {
	return getIdentityFromClient(ctx, client)
}

func getIdentityFromClient(ctx context.Context, client STSClient) (*models.Identity, error) {
	out, err := client.GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	if err != nil {
		return nil, fmt.Errorf("sts:GetCallerIdentity failed: %w\n\nFix: ensure valid AWS credentials are configured and not expired", err)
	}
	return &models.Identity{
		AccountID: aws.ToString(out.Account),
		ARN:       aws.ToString(out.Arn),
		UserID:    aws.ToString(out.UserId),
	}, nil
}

// loadAWSConfig builds an aws.Config honouring the CLI's global flags.
func loadAWSConfig(ctx context.Context, region, profile string) (aws.Config, error) {
	opts := []func(*config.LoadOptions) error{}
	if region != "" {
		opts = append(opts, config.WithRegion(region))
	}
	if profile != "" {
		opts = append(opts, config.WithSharedConfigProfile(profile))
	}
	return config.LoadDefaultConfig(ctx, opts...)
}

// NewAWSConfig returns an aws.Config for use outside awsctx (e.g., catalogue, monitor).
func NewAWSConfig(ctx context.Context, region, profile string) (aws.Config, error) {
	return loadAWSConfig(ctx, region, profile)
}
