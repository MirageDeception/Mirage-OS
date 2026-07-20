package abuse

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials/stscreds"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/fatih/color"
	"github.com/mirage-security/mirage/internal/catalogue"
	"github.com/mirage-security/mirage/internal/discovery"
	"github.com/mirage-security/mirage/pkg/models"
)

type AttackConfig struct {
	AWSConfig      aws.Config
	Catalogue      catalogue.Store
	TemplatesPath  string
	TargetScenario int
	Identity       *models.Identity
	SpokeAlias     string
}

func RunAttack(ctx context.Context, cfg AttackConfig) error {
	resources, err := cfg.Catalogue.ListResources(ctx, catalogue.ResourceFilter{
		AccountID:   cfg.Identity.AccountID,
		ScenarioNum: cfg.TargetScenario,
		Status:      "active",
	})
	if err != nil {
		return fmt.Errorf("failed to list deployed resources: %w", err)
	}

	if len(resources) == 0 {
		return fmt.Errorf("scenario %d is not currently deployed", cfg.TargetScenario)
	}

	scanner := discovery.NewScanner(cfg.TemplatesPath)
	manifest, err := scanner.GetScenario(cfg.TargetScenario)
	if err != nil {
		return fmt.Errorf("failed to load scenario manifest: %w", err)
	}

	color.Cyan("\n▶ Attack Path (as defined by scenario):")
	for i, step := range manifest.AttackPath {
		color.Cyan("  %d. %s", i+1, step)
	}

	// 1. Find role to assume, and target resource to attack
	var roleARN string
	var targetResource models.Resource

	for _, r := range resources {
		if r.ResourceType == "iam_role" {
			roleARN = r.ARN
		} else {
			targetResource = r
		}
	}

	attackCfg := cfg.AWSConfig
	var clientIdentity string

	if roleARN != "" {
		color.Yellow("\n[ATTACK] Assuming lure IAM Role: %s", roleARN)
		stsClient := sts.NewFromConfig(cfg.AWSConfig)
		creds := stscreds.NewAssumeRoleProvider(stsClient, roleARN, func(opts *stscreds.AssumeRoleOptions) {
			opts.RoleSessionName = "MirageAbuseSimulation"
		})
		
		attackCfg.Credentials = aws.NewCredentialsCache(creds)
		clientIdentity = fmt.Sprintf("AssumedRole: %s", roleARN)
	} else {
		color.Yellow("\n[ATTACK] No lure role defined. Attacking using current identity.")
		clientIdentity = cfg.Identity.ARN
	}

	color.Yellow("[ATTACK] Attacking Decoy (%s)...", targetResource.ResourceName)

	var attackErr error
	switch strings.ToLower(manifest.Service) {
	case "s3":
		client := s3.NewFromConfig(attackCfg)
		_, attackErr = client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
			Bucket: aws.String(targetResource.ResourceName),
		})
	case "secretsmanager":
		client := secretsmanager.NewFromConfig(attackCfg)
		_, attackErr = client.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
			SecretId: aws.String(targetResource.ARN),
		})
	case "dynamodb":
		client := dynamodb.NewFromConfig(attackCfg)
		_, attackErr = client.Scan(ctx, &dynamodb.ScanInput{
			TableName: aws.String(targetResource.ResourceName),
		})
	case "ssm":
		client := ssm.NewFromConfig(attackCfg)
		_, attackErr = client.GetParameter(ctx, &ssm.GetParameterInput{
			Name: aws.String(targetResource.ResourceName),
		})
	default:
		return fmt.Errorf("abuse for service %s not yet implemented in CLI. Run a manual API call.", manifest.Service)
	}

	if attackErr != nil {
		// Even if the API call fails (e.g. Access Denied), the CloudTrail event is often still generated.
		color.Magenta("[ATTACK RESULT] API call returned error: %v", attackErr)
		color.Magenta("  (Note: Many decoys intentionally deny access to trap attackers. CloudTrail will still log the attempt.)")
	} else {
		color.Magenta("[ATTACK RESULT] API call succeeded against the decoy.")
	}

	color.Green("\nAttack simulation complete. Real alert delivered.")
	color.Green("Check SOC inbox within ~12 seconds.")

	// Audit Log
	_ = cfg.Catalogue.LogOperation(ctx, models.Operation{
		Timestamp:   time.Now(),
		Operator:    cfg.Identity.ARN,
		Command:     fmt.Sprintf("scenario abuse %d", cfg.TargetScenario),
		AccountID:   cfg.Identity.AccountID,
		SpokeAlias:  cfg.SpokeAlias,
		ScenarioNum: cfg.TargetScenario,
		Action:      "abuse",
		Result:      "success",
		Details:     fmt.Sprintf("Abuse executed via %s against %s", clientIdentity, targetResource.ARN),
	})

	return nil
}
