// Package naming implements the deception resource naming resolution engine.
//
// The naming system is the core mechanism for deception blending. It resolves
// template placeholder patterns into realistic resource names that match the
// operator's existing infrastructure naming conventions.
//
// Resolution order (highest wins):
//  1. CLI flag (--name-prefix)
//  2. Config override (naming.overrides.scenario-N.resource_type)
//  3. Config pattern (naming.patterns.resource_type)
//  4. Terraform variable default ("__PLACEHOLDER__" — never reaches AWS)
package naming

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"regexp"
	"strings"

	"github.com/mirage-security/mirage/internal/config"
)

// Resolver resolves resource names from config patterns.
type Resolver struct {
	cfg        *config.Config
	accountID  string
	region     string
	spokeAlias string
	// flagPrefix overrides naming.prefix for this invocation only.
	flagPrefix string
}

// NewResolver creates a new naming resolver.
// accountID, region, and spokeAlias are provided at runtime from STS identity.
func NewResolver(cfg *config.Config, accountID, region, spokeAlias string) *Resolver {
	return &Resolver{
		cfg:        cfg,
		accountID:  accountID,
		region:     region,
		spokeAlias: spokeAlias,
	}
}

// WithFlagPrefix sets a one-off prefix override (--name-prefix flag).
func (r *Resolver) WithFlagPrefix(prefix string) *Resolver {
	r.flagPrefix = prefix
	return r
}

// Resolve returns the resolved name for a given scenario and resource type.
// scenarioKey is the string key used in naming.overrides (e.g., "scenario-1").
// resourceType is the config key (e.g., "s3_bucket", "iam_role").
// slug is the scenario's slug string (e.g., "terraform-state").
// extraVars are additional {key} = value pairs for pattern interpolation.
func (r *Resolver) Resolve(scenarioKey, resourceType, slug string, extraVars map[string]string) (string, error) {
	// Step 1: Check config.naming.overrides.scenario-N.resource_type
	if r.cfg.Naming.Overrides != nil {
		if scenarioOverrides, ok := r.cfg.Naming.Overrides[scenarioKey]; ok {
			if override, ok := scenarioOverrides[resourceType]; ok && override != "" {
				return override, nil
			}
		}
	}

	// Step 2: Get pattern from config.naming.patterns.resource_type
	pattern := r.patternForType(resourceType)
	if pattern == "" {
		return "__PLACEHOLDER__", nil
	}

	// Step 3: Resolve prefix (flag > config)
	prefix := r.cfg.Naming.Prefix
	if r.flagPrefix != "" {
		prefix = r.flagPrefix
	}

	// Step 4: Generate suffix (4-char hex derived from account + scenario for determinism)
	suffix := deterministicSuffix(r.accountID, scenarioKey)

	// Step 5: Build variable map
	vars := map[string]string{
		"prefix":        prefix,
		"scenario_slug": slug,
		"suffix":        suffix,
		"region":        r.region,
		"account_id":    r.accountID,
		"spoke_alias":   r.spokeAlias,
	}
	// Merge extra vars (caller-provided key values, e.g., {key} for SSM paths)
	for k, v := range extraVars {
		vars[k] = v
	}

	// Step 6: Interpolate pattern
	resolved, err := interpolate(pattern, vars)
	if err != nil {
		return "", fmt.Errorf("resolve %s/%s: %w", scenarioKey, resourceType, err)
	}

	return resolved, nil
}

// ResolveAll resolves names for all resource types declared in a scenario manifest.
// Returns a map of resourceType → resolvedName.
func (r *Resolver) ResolveAll(scenarioKey, slug string, resourceTypes []string, extraVars map[string]string) (map[string]string, error) {
	result := make(map[string]string, len(resourceTypes))
	for _, rt := range resourceTypes {
		name, err := r.Resolve(scenarioKey, rt, slug, extraVars)
		if err != nil {
			return nil, err
		}
		result[rt] = name
	}
	return result, nil
}

// CheckCollisions validates that no two scenarios produce the same resource name
// for the same resource type. Returns a list of collision descriptions.
func (r *Resolver) CheckCollisions(scenarios []ScenarioNameInput) []string {
	seen := make(map[string]string) // "resource_type:name" → first scenarioKey
	var collisions []string

	for _, s := range scenarios {
		for _, rt := range s.ResourceTypes {
			name, err := r.Resolve(s.ScenarioKey, rt, s.Slug, s.ExtraVars)
			if err != nil {
				continue
			}
			key := rt + ":" + name
			if first, exists := seen[key]; exists {
				collisions = append(collisions,
					fmt.Sprintf("collision: %s and %s both resolve %s to %q",
						first, s.ScenarioKey, rt, name))
			} else {
				seen[key] = s.ScenarioKey
			}
		}
	}
	return collisions
}

// ScenarioNameInput is the input for a single scenario in collision checking.
type ScenarioNameInput struct {
	ScenarioKey   string
	Slug          string
	ResourceTypes []string
	ExtraVars     map[string]string
}

// patternForType returns the naming pattern for a resource type key.
func (r *Resolver) patternForType(resourceType string) string {
	p := r.cfg.Naming.Patterns
	switch strings.ToLower(resourceType) {
	case "s3_bucket":
		return p.S3Bucket
	case "iam_role":
		return p.IAMRole
	case "lambda_function", "lambda":
		return p.LambdaFunction
	case "ssm_parameter":
		return p.SSMParameter
	case "dynamodb_table":
		return p.DynamoDBTable
	case "sqs_queue":
		return p.SQSQueue
	case "sns_topic":
		return p.SNSTopic
	case "kms_key_alias", "kms":
		return p.KMSKeyAlias
	case "secrets_manager", "secretsmanager":
		return p.SecretsManager
	case "ecr_repository", "ecr":
		return p.ECRRepository
	case "cloudwatch_log_group", "log_group":
		return p.CloudWatchLG
	default:
		return ""
	}
}

// interpolate replaces {variable} placeholders in a pattern with values from vars.
// Returns an error if any placeholder in the pattern is missing from vars.
var placeholderRe = regexp.MustCompile(`\{(\w+)\}`)

func interpolate(pattern string, vars map[string]string) (string, error) {
	var missing []string
	result := placeholderRe.ReplaceAllStringFunc(pattern, func(match string) string {
		key := match[1 : len(match)-1] // strip { }
		val, ok := vars[key]
		if !ok {
			missing = append(missing, key)
			return match
		}
		return val
	})
	if len(missing) > 0 {
		return "", fmt.Errorf("unresolved variables: %v (pattern: %q)", missing, pattern)
	}
	return result, nil
}

// deterministicSuffix generates a 4-char lowercase hex suffix from account ID and scenario key.
// This is deterministic (re-running produces the same suffix) but looks like a random ID.
func deterministicSuffix(accountID, scenarioKey string) string {
	// Use the last 4 chars of the account ID XOR'd with the scenario number.
	seed := accountID + scenarioKey
	// Simple: take last 4 hex chars of a fnv-like hash.
	h := uint32(2166136261)
	for _, c := range seed {
		h ^= uint32(c)
		h *= 16777619
	}
	return fmt.Sprintf("%04x", h&0xFFFF)
}

// RandomSuffix generates a cryptographically random 4-char hex suffix.
// Used when a non-deterministic suffix is preferred (e.g. testing).
func RandomSuffix() string {
	b := make([]byte, 2)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(256))
		b[i] = byte(n.Int64())
	}
	return fmt.Sprintf("%x", b)
}
