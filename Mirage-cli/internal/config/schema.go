// Package config defines the config schema that maps to ~/.mirage/config.yaml.
package config

// Config is the top-level config structure. No secrets or account IDs should be
// committed to version control — this file is local to the operator's machine.
type Config struct {
	Version    string     `yaml:"version"`    // config schema version
	Cloud      string     `yaml:"cloud"`      // aws | azure | gcp | k8s
	Region     string     `yaml:"region"`
	Accounts   Accounts   `yaml:"accounts"`
	Alerts     Alerts     `yaml:"alerts"`
	Naming     Naming     `yaml:"naming"`
	Catalogue  Catalogue  `yaml:"catalogue"`
	Templates  Templates  `yaml:"templates"`
	Monitoring Monitoring `yaml:"monitoring"`
	Operational Operational `yaml:"operational"`
}

// Accounts holds the hub and all spoke account configurations.
type Accounts struct {
	Hub    HubAccount    `yaml:"hub"`
	Spokes []SpokeAccount `yaml:"spokes"`
}

// HubAccount is the management and monitoring account.
type HubAccount struct {
	ID         string `yaml:"id"`
	Alias      string `yaml:"alias"`
	OrgManaged bool   `yaml:"org_managed"`
}

// SpokeAccount is one deception target account.
type SpokeAccount struct {
	ID                  string `yaml:"id"`
	Alias               string `yaml:"alias"`
	Environment         string `yaml:"environment,omitempty"`
	DeploymentRoleARN   string `yaml:"deployment_role_arn,omitempty"`
	ForwardingRoleARN   string `yaml:"forwarding_role_arn,omitempty"`
	RolesDeployed       bool   `yaml:"roles_deployed"`
	ForwardingDeployed  bool   `yaml:"forwarding_deployed"`
	AuthorizedOnBus     bool   `yaml:"authorized_on_bus"`
}

// Alerts configures where detection alerts are sent.
type Alerts struct {
	Emails []string `yaml:"emails"`
}

// Naming controls how deception resources are named to blend with real infra.
type Naming struct {
	Prefix    string                       `yaml:"prefix"`
	Separator string                       `yaml:"separator"`
	Patterns  NamingPatterns               `yaml:"patterns"`
	Overrides map[string]map[string]string `yaml:"overrides,omitempty"` // scenario-N -> type -> name
}

// NamingPatterns defines the default naming template for each resource type.
// Variables: {prefix}, {scenario_slug}, {suffix}, {key}, {region}, {account_id}, {spoke_alias}
type NamingPatterns struct {
	S3Bucket          string `yaml:"s3_bucket"`
	IAMRole           string `yaml:"iam_role"`
	LambdaFunction    string `yaml:"lambda_function"`
	SSMParameter      string `yaml:"ssm_parameter"`
	DynamoDBTable     string `yaml:"dynamodb_table"`
	SQSQueue          string `yaml:"sqs_queue"`
	SNSTopic          string `yaml:"sns_topic"`
	KMSKeyAlias       string `yaml:"kms_key_alias"`
	SecretsManager    string `yaml:"secrets_manager"`
	ECRRepository     string `yaml:"ecr_repository"`
	CloudWatchLG      string `yaml:"cloudwatch_log_group"`
}

// Catalogue configures the resource state backend.
type Catalogue struct {
	Backend    string         `yaml:"backend"` // sqlite | dynamodb
	SQLitePath string         `yaml:"sqlite_path,omitempty"`
	DynamoDB   *DynamoDBCfg   `yaml:"dynamodb,omitempty"`
}

// DynamoDBCfg is only used when catalogue.backend = "dynamodb".
type DynamoDBCfg struct {
	TableName string `yaml:"table_name"`
	Region    string `yaml:"region"`
}

// Templates configures where Terraform scenario templates are fetched from.
type Templates struct {
	Source string        `yaml:"source"` // github | local | s3
	GitHub *GitHubSource `yaml:"github,omitempty"`
	Local  *LocalSource  `yaml:"local,omitempty"`
	S3     *S3Source     `yaml:"s3,omitempty"`
}

// GitHubSource fetches templates from a GitHub repository.
type GitHubSource struct {
	Repo   string `yaml:"repo"`
	Branch string `yaml:"branch"`
	Path   string `yaml:"path"`
}

// LocalSource fetches templates from a local filesystem path.
type LocalSource struct {
	Path string `yaml:"path"`
}

// S3Source fetches templates from an S3 bucket (future).
type S3Source struct {
	Bucket string `yaml:"bucket"`
	Prefix string `yaml:"prefix"`
}

// Monitoring configures the detection pipeline parameters.
type Monitoring struct {
	EventBusName        string   `yaml:"event_bus_name"`
	LambdaRuntime       string   `yaml:"lambda_runtime"`
	AlertSeverityLevels []string `yaml:"alert_severity_levels"`
	BrainLambdaARN      string   `yaml:"brain_lambda_arn,omitempty"`
	SNSTopicARN         string   `yaml:"sns_topic_arn,omitempty"`
	EventBusARN         string   `yaml:"event_bus_arn,omitempty"`
}

// Operational controls runtime behaviour of the CLI.
type Operational struct {
	AutoVerifyAfterDeploy bool `yaml:"auto_verify_after_deploy"`
	VerifyTimeoutSeconds  int  `yaml:"verify_timeout_seconds"`
	MaxParallelDeploys    int  `yaml:"max_parallel_deploys"`
}
