package config

import (
	"os"
	"path/filepath"
)

// Defaults returns a Config pre-populated with sensible default values.
// Used by `mirage init` as the starting template.
func Defaults() *Config {
	home, _ := os.UserHomeDir()
	return &Config{
		Version: CurrentVersion,
		Cloud:   "aws",
		Region:  "us-west-2",
		Naming: Naming{
			Prefix:    "corp",
			Separator: "-",
			Patterns: NamingPatterns{
				S3Bucket:       "{prefix}-{scenario_slug}-{suffix}",
				IAMRole:        "{prefix}-{scenario_slug}-role",
				LambdaFunction: "{prefix}-{scenario_slug}-fn",
				SSMParameter:   "/{prefix}/{scenario_slug}/{key}",
				DynamoDBTable:  "{prefix}-{scenario_slug}-table",
				SQSQueue:       "{prefix}-{scenario_slug}-queue",
				SNSTopic:       "{prefix}-{scenario_slug}-topic",
				KMSKeyAlias:    "alias/{prefix}-{scenario_slug}",
				SecretsManager: "{prefix}/{scenario_slug}/{key}",
				ECRRepository:  "{prefix}-{scenario_slug}",
				CloudWatchLG:   "/aws/{prefix}/{scenario_slug}",
			},
		},
		Catalogue: Catalogue{
			Backend:    "sqlite",
			SQLitePath: filepath.Join(home, ".mirage", "catalogue.db"),
		},
		Templates: Templates{
			Source: "local",
			Local: &LocalSource{
				// Default: bundled AWS scenarios in the same repo.
				Path: "../../aws/scenarios_terraform",
			},
		},
		Monitoring: Monitoring{
			EventBusName:  "deception-global-event-bus",
			LambdaRuntime: "python3.11",
			AlertSeverityLevels: []string{"CRITICAL", "HIGH"},
		},
		Operational: Operational{
			AutoVerifyAfterDeploy: false,
			VerifyTimeoutSeconds:  30,
			MaxParallelDeploys:    5,
		},
	}
}
