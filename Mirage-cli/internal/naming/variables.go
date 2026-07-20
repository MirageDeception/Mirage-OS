// Package naming — variables.go
// Extracts the declared Terraform variables from a scenario's variables.tf file.
// This allows the naming engine to generate only the variables a given template
// actually declares, avoiding "variable not declared" Terraform errors.
package naming

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// variableRe matches `variable "name" {` in a .tf file.
var variableRe = regexp.MustCompile(`^\s*variable\s+"([^"]+)"\s*\{`)

// ExtractTFVariables parses a variables.tf file and returns all declared variable names.
// Returns an empty slice if the file doesn't exist (graceful degradation).
func ExtractTFVariables(variablesTFPath string) ([]string, error) {
	f, err := os.Open(variablesTFPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil // no variables declared is valid
		}
		return nil, fmt.Errorf("open %s: %w", variablesTFPath, err)
	}
	defer f.Close()

	var names []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if m := variableRe.FindStringSubmatch(line); len(m) == 2 {
			names = append(names, m[1])
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan %s: %w", variablesTFPath, err)
	}
	return names, nil
}

// FilterVarsToDeclarations filters a vars map to only include keys that are
// declared in the given Terraform variables list. This prevents "variable not
// declared" errors when calling terraform with extra vars.
//
// If declared is empty/nil, all vars are returned unchanged (safe fallback).
func FilterVarsToDeclarations(vars map[string]string, declared []string) map[string]string {
	if len(declared) == 0 {
		return vars
	}

	allowed := make(map[string]struct{}, len(declared))
	for _, d := range declared {
		allowed[d] = struct{}{}
	}

	filtered := make(map[string]string, len(declared))
	for k, v := range vars {
		if _, ok := allowed[k]; ok {
			filtered[k] = v
		}
	}
	return filtered
}

// BuildVarMap constructs the full variable map for a scenario from resolved names.
// The map is suitable for passing to tf.WriteTempVarFile.
//
// Parameters:
//   - accountID: current spoke account ID (always included)
//   - region: current region
//   - resolvedNames: resource type → resolved resource name map
//   - scenarioOutputs: terraform output names from scenario manifest
func BuildVarMap(accountID, region string, resolvedNames map[string]string, extra map[string]string) map[string]string {
	vars := map[string]string{
		"account_id": accountID,
		"region":     region,
	}
	for k, v := range resolvedNames {
		// Normalize resource type keys to match Terraform variable naming:
		// s3_bucket → bucket_name, iam_role → role_name, etc.
		tfKey := resourceTypeToTFVar(k)
		vars[tfKey] = v
		// Also include raw key for flexibility.
		vars[k] = v
	}
	for k, v := range extra {
		vars[k] = v
	}
	return vars
}

// resourceTypeToTFVar converts a resource type key to a likely Terraform variable name.
// E.g. "s3_bucket" → "bucket_name", "iam_role" → "role_name".
func resourceTypeToTFVar(resourceType string) string {
	switch strings.ToLower(resourceType) {
	case "s3_bucket":
		return "bucket_name"
	case "iam_role":
		return "role_name"
	case "lambda_function", "lambda":
		return "function_name"
	case "ssm_parameter":
		return "parameter_name"
	case "dynamodb_table":
		return "table_name"
	case "sqs_queue":
		return "queue_name"
	case "sns_topic":
		return "topic_name"
	case "kms_key_alias", "kms":
		return "key_alias"
	case "secrets_manager", "secretsmanager":
		return "secret_name"
	case "ecr_repository", "ecr":
		return "repository_name"
	case "cloudwatch_log_group", "log_group":
		return "log_group_name"
	default:
		return resourceType
	}
}
