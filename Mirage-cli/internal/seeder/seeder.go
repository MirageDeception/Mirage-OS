// Package seeder uploads fake deception data into deployed AWS resources.
//
// All seeded content includes the marker "MIRAGE-DECEPTION-FABRICATED-EXPIRED"
// so IR teams immediately distinguish deception artifacts from real credentials.
//
// Source files are read from fake-data/ inside the scenario directory.
// If a source file is absent, synthetic content is generated in memory.
package seeder

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	ssmtypes "github.com/aws/aws-sdk-go-v2/service/ssm/types"

	"github.com/mirage-security/mirage/pkg/models"
)

// Marker embedded in every seeded artifact. Never remove or change this string.
const Marker = "MIRAGE-DECEPTION-FABRICATED-EXPIRED"

// Seeder uploads fake data using AWS SDK clients scoped to the correct account.
type Seeder struct {
	s3  *s3.Client
	ssm *ssm.Client
	ddb *dynamodb.Client
	sm  *secretsmanager.Client
}

// New creates a Seeder from an aws.Config already scoped to the target account/region.
func New(cfg aws.Config) *Seeder {
	return &Seeder{
		s3:  s3.NewFromConfig(cfg),
		ssm: ssm.NewFromConfig(cfg),
		ddb: dynamodb.NewFromConfig(cfg),
		sm:  secretsmanager.NewFromConfig(cfg),
	}
}

// Result captures the outcome of a single seed operation.
type Result struct {
	Kind string
	Key  string
	OK   bool
	Err  error
}

// SeedAll processes every seed item declared in the scenario manifest.
//
//   - tfOutputs: terraform output key → value (e.g. "bucket_name" → "corp-state-a1b2")
//   - scenarioDir: path containing the scenario's fake-data/ subfolder
func (s *Seeder) SeedAll(ctx context.Context, manifest *models.ScenarioManifest, tfOutputs map[string]string, scenarioDir string) []Result {
	results := make([]Result, 0, len(manifest.Seed))
	for _, item := range manifest.Seed {
		var err error
		switch strings.ToLower(item.Kind) {
		case "s3":
			err = s.seedS3(ctx, item, tfOutputs, scenarioDir)
		case "ssm":
			err = s.seedSSM(ctx, item, tfOutputs)
		case "dynamodb":
			err = s.seedDynamoDB(ctx, item, tfOutputs, manifest.Number)
		case "secretsmanager":
			err = s.seedSecretsManager(ctx, item, tfOutputs)
		default:
			err = fmt.Errorf("unknown seed kind %q", item.Kind)
		}
		results = append(results, Result{
			Kind: item.Kind,
			Key:  item.DestinationKey,
			OK:   err == nil,
			Err:  err,
		})
	}
	return results
}

// ── S3 ────────────────────────────────────────────────────────────────────────

func (s *Seeder) seedS3(ctx context.Context, item models.SeedItem, outputs map[string]string, scenarioDir string) error {
	bucket := firstNonEmpty(outputs["bucket_name"], outputs["bucket"])
	if bucket == "" {
		return fmt.Errorf("s3 seed: bucket_name not in terraform outputs")
	}

	body := readOrGenerate(
		filepath.Join(scenarioDir, "fake-data", filepath.Base(item.Source)),
		fakeTFState(item.DestinationKey),
	)

	_, err := s.s3.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(item.DestinationKey),
		Body:        bytes.NewReader(body),
		ContentType: aws.String("application/json"),
	})
	return wrapf(err, "s3:PutObject s3://%s/%s", bucket, item.DestinationKey)
}

// ── SSM ───────────────────────────────────────────────────────────────────────

func (s *Seeder) seedSSM(ctx context.Context, item models.SeedItem, outputs map[string]string) error {
	name := firstNonEmpty(outputs["parameter_name"], item.DestinationKey)
	value := fmt.Sprintf(`{"note":%q,"generated":%q,"content":"PLACEHOLDER_CREDENTIALS_DO_NOT_USE"}`,
		Marker, time.Now().UTC().Format(time.RFC3339))

	_, err := s.ssm.PutParameter(ctx, &ssm.PutParameterInput{
		Name:      aws.String(name),
		Value:     aws.String(value),
		Type:      ssmtypes.ParameterTypeSecureString,
		Overwrite: aws.Bool(true),
		Tags: []ssmtypes.Tag{
			{Key: aws.String("ManagedBy"), Value: aws.String("mirage")},
			{Key: aws.String("MirageMarker"), Value: aws.String(Marker)},
		},
	})
	return wrapf(err, "ssm:PutParameter %s", name)
}

// ── DynamoDB ──────────────────────────────────────────────────────────────────

func (s *Seeder) seedDynamoDB(ctx context.Context, item models.SeedItem, outputs map[string]string, scenarioNum int) error {
	table := firstNonEmpty(outputs["table_name"], outputs["primary_table_name"])
	if table == "" {
		return fmt.Errorf("dynamodb seed: table_name not in terraform outputs")
	}

	_, err := s.ddb.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(table),
		Item: map[string]types.AttributeValue{
			"id":         &types.AttributeValueMemberS{Value: fmt.Sprintf("mirage-decoy-%d", scenarioNum)},
			"marker":     &types.AttributeValueMemberS{Value: Marker},
			"data":       &types.AttributeValueMemberS{Value: `{"note":"DECEPTION_RECORD_DO_NOT_USE"}`},
			"created_at": &types.AttributeValueMemberS{Value: time.Now().UTC().Format(time.RFC3339)},
		},
	})
	return wrapf(err, "dynamodb:PutItem %s", table)
}

// ── SecretsManager ────────────────────────────────────────────────────────────

func (s *Seeder) seedSecretsManager(ctx context.Context, item models.SeedItem, outputs map[string]string) error {
	name := firstNonEmpty(outputs["secret_name"], item.DestinationKey)
	value := fmt.Sprintf(`{"note":%q,"api_key":"EXPIRED_PLACEHOLDER_DO_NOT_USE","generated":%q}`,
		Marker, time.Now().UTC().Format(time.RFC3339))

	_, err := s.sm.PutSecretValue(ctx, &secretsmanager.PutSecretValueInput{
		SecretId:     aws.String(name),
		SecretString: aws.String(value),
	})
	return wrapf(err, "secretsmanager:PutSecretValue %s", name)
}

// ── helpers ───────────────────────────────────────────────────────────────────

func readOrGenerate(path string, fallback []byte) []byte {
	data, err := os.ReadFile(path)
	if err != nil {
		return fallback
	}
	return data
}

func fakeTFState(key string) []byte {
	safeKey := strings.ToUpper(strings.NewReplacer("/", "_", ".", "_").Replace(key))
	return []byte(fmt.Sprintf(`{
  "version": 4,
  "terraform_version": "1.5.7",
  "_NOTICE": %q,
  "serial": 1,
  "lineage": "00000000-0000-0000-0000-000000000000",
  "outputs": {
    "deploy_role_arn": {
      "value": "arn:aws:iam::000000000000:role/EXPIRED_PLACEHOLDER_%s"
    }
  },
  "resources": []
}`, Marker, safeKey))
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

func wrapf(err error, format string, args ...interface{}) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf(format+": %w", append(args, err)...)
}
