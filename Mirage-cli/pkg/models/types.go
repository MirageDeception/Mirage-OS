// Package models defines shared types used across all mirage packages.
package models

import "time"

// AccountRole classifies the current AWS account relative to the mirage config.
type AccountRole string

const (
	RoleHub     AccountRole = "hub"
	RoleSpoke   AccountRole = "spoke"
	RoleUnknown AccountRole = "unknown"
)

// Identity holds the result of sts:GetCallerIdentity.
type Identity struct {
	AccountID string
	ARN       string
	UserID    string
}

// SpokeConfig represents a spoke account in the config.
type SpokeConfig struct {
	ID                  string `yaml:"id"`
	Alias               string `yaml:"alias"`
	Environment         string `yaml:"environment,omitempty"`
	DeploymentRoleARN   string `yaml:"deployment_role_arn,omitempty"`
	ForwardingRoleARN   string `yaml:"forwarding_role_arn,omitempty"`
	RolesDeployed       bool   `yaml:"roles_deployed"`
	ForwardingDeployed  bool   `yaml:"forwarding_deployed"`
	AuthorizedOnBus     bool   `yaml:"authorized_on_bus"`
}

// Resource represents a single deployed deception resource in the catalogue.
type Resource struct {
	ID            int64     `db:"id"`
	AccountID     string    `db:"account_id"`
	SpokeAlias    string    `db:"spoke_alias"`
	ScenarioNum   int       `db:"scenario_num"`
	ScenarioName  string    `db:"scenario_name"`
	ResourceType  string    `db:"resource_type"`
	ResourceName  string    `db:"resource_name"`
	ARN           string    `db:"arn"`
	DeployedAt    time.Time `db:"deployed_at"`
	DestroyedAt   *time.Time `db:"destroyed_at"`
	LastVerified  *time.Time `db:"last_verified"`
	DeployedBy    string    `db:"deployed_by"`
	TFStatePath   string    `db:"tf_state_path"`
	Status        string    `db:"status"` // active | destroyed | orphaned | unknown
}

// Operation represents a single entry in the audit log.
type Operation struct {
	ID          int64     `db:"id"`
	Timestamp   time.Time `db:"timestamp"`
	Operator    string    `db:"operator"`
	Command     string    `db:"command"`
	AccountID   string    `db:"account_id"`
	SpokeAlias  string    `db:"spoke_alias"`
	ScenarioNum int       `db:"scenario_num"`
	Action      string    `db:"action"` // deploy | destroy | abuse | verify | import
	Result      string    `db:"result"` // success | failure | dry-run
	Details     string    `db:"details"` // JSON blob
}

// ScenarioManifest holds parsed scenario.yaml metadata.
type ScenarioManifest struct {
	Number      int              `yaml:"number"`
	Name        string           `yaml:"name"`
	Slug        string           `yaml:"slug"`
	Version     string           `yaml:"version"`
	Category    string           `yaml:"category"` // credential-theft | data-exfil | lateral-movement | privilege-escalation
	Service     string           `yaml:"service"`  // primary AWS service
	Description string           `yaml:"description"`
	Resources   []ScenarioResource `yaml:"resources"`
	Seed        []SeedItem       `yaml:"seed"`
	Detection   DetectionConfig  `yaml:"detection"`
	Terraform   TerraformConfig  `yaml:"terraform"`
	AttackPath  []string         `yaml:"attack_path"`
}

// ScenarioResource describes a resource within a scenario.
type ScenarioResource struct {
	Type       string `yaml:"type"`       // s3_bucket, iam_role, lambda, etc.
	TFVariable string `yaml:"tf_variable"` // the terraform variable name
	Purpose    string `yaml:"purpose"`
}

// SeedItem describes fake data to upload post-deploy.
type SeedItem struct {
	Kind           string `yaml:"kind"`            // s3 | ssm | dynamodb | secretsmanager
	Source         string `yaml:"source"`          // local file path
	DestinationKey string `yaml:"destination_key"` // S3 key / SSM path / secret name
}

// DetectionConfig describes the CloudTrail events that signal this decoy was touched.
type DetectionConfig struct {
	Events   []DetectionEvent `yaml:"events"`
	Severity string           `yaml:"severity"` // CRITICAL | HIGH | MEDIUM
}

// DetectionEvent is one CloudTrail event pattern for EventBridge matching.
type DetectionEvent struct {
	Source     string   `yaml:"source"`
	DetailType string   `yaml:"detail_type"`
	APICalls   []string `yaml:"api_calls"`
}

// TerraformConfig describes the Terraform requirements for a scenario.
type TerraformConfig struct {
	RequiredVariables []string `yaml:"required_variables"`
	Outputs           []string `yaml:"outputs"`
}

// TerraformResult holds the outcome of a terraform operation.
type TerraformResult struct {
	Success  bool
	Outputs  map[string]string
	PlanPath string
	Error    error
	Stderr   string
}

// SyncReport is the result of catalogue sync against live AWS state.
type SyncReport struct {
	Orphaned []Resource // in catalogue, not in AWS
	Phantom  []Resource // in AWS, not in catalogue
	InSync   []Resource // matches
}

// StatusMatrix is the full end-to-end health view.
type StatusMatrix struct {
	HubPlane  HubStatus
	Spokes    []SpokeStatus
}

// HubStatus represents the hub plane health.
type HubStatus struct {
	BrainDeployed        bool
	DetectionRuleCount   int
	ExpectedRuleCount    int
	AuthorizedSpokes     []string
	SNSSubscriptions     []SNSSubscription
}

// SpokeStatus represents a single spoke's health.
type SpokeStatus struct {
	Alias              string
	AccountID          string
	ForwardingDeployed bool
	ForwardingEnabled  bool
	DeployedScenarios  []int
	HealthMatrix       []ScenarioHealth
}

// ScenarioHealth is one row in the status matrix.
type ScenarioHealth struct {
	Number       int
	Name         string
	Deployed     bool
	Forwarded    bool
	RuleExists   bool
	AlertPath    bool
	LastVerified *time.Time
}

// SNSSubscription tracks email alert subscriptions.
type SNSSubscription struct {
	Email    string
	Status   string // Confirmed | PendingConfirmation
	ARN      string
}
