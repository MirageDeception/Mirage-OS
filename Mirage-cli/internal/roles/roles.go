// Package roles manages cross-account IAM role lifecycle for the mirage deception CLI.
// Roles are prerequisites for all other operations — deploy them first.
package roles

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	awssts "github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/tf"
)

const (
	DeploymentRoleName = "mirage-deployment-role"
	ForwardingRoleName = "mirage-forwarding-role"
	ExternalIDPrefix   = "mirage-deployment-"
)

// ExternalID returns the ExternalId string for a spoke alias.
func ExternalID(spokeAlias string) string {
	return ExternalIDPrefix + spokeAlias
}

// DeployResult captures ARNs written to config after successful deployment.
type DeployResult struct {
	SpokeAlias        string
	DeploymentRoleARN string
	ForwardingRoleARN string
}

// DeployForSpoke deploys both IAM roles into a spoke account via Terraform.
// It injects cross-account credentials obtained by assuming a bootstrap role
// (or using the current profile if already in the spoke account).
//
// Parameters:
//   - hubAccountID: the hub account that will assume the deployment role
//   - spoke: spoke account config entry
//   - runner: tf.Runner (may have credentials pre-injected for cross-account)
//   - templatesDir: path to Mirage-cli/templates/roles/
//   - mirageDir: ~/.mirage/ for isolated state storage
//   - dryRun: if true, shows plan only
func DeployForSpoke(
	ctx context.Context,
	hubAccountID string,
	spoke config.SpokeAccount,
	runner *tf.Runner,
	templatesDir, mirageDir string,
	dryRun bool,
) (*DeployResult, error) {
	result := &DeployResult{SpokeAlias: spoke.Alias}

	// ── Deployment Role ─────────────────────────────────────────
	deployWorkDir := filepath.Join(templatesDir, "spoke-deployment-role")
	deployStatePath := tf.StatePath(mirageDir, "roles", spoke.Alias, "deployment-role")

	if err := tf.EnsureStateDir(deployStatePath); err != nil {
		return nil, err
	}
	if err := tf.WriteBackendOverride(deployWorkDir, deployStatePath); err != nil {
		return nil, err
	}
	defer tf.RemoveBackendOverride(deployWorkDir)

	deployVars := map[string]string{
		"hub_account_id":       hubAccountID,
		"spoke_account_id":     spoke.ID,
		"spoke_alias":          spoke.Alias,
		"deployment_role_name": DeploymentRoleName,
		"external_id":          ExternalID(spoke.Alias),
	}

	deployRes, err := runner.ApplyWithVars(ctx, deployWorkDir, deployVars, dryRun)
	if err != nil {
		return nil, fmt.Errorf("deploy deployment-role in spoke %s: %w", spoke.Alias, err)
	}
	if !dryRun {
		result.DeploymentRoleARN = deployRes.Outputs["deployment_role_arn"]
	}

	// ── Forwarding Role ──────────────────────────────────────────
	fwdWorkDir := filepath.Join(templatesDir, "spoke-forwarding-role")
	fwdStatePath := tf.StatePath(mirageDir, "roles", spoke.Alias, "forwarding-role")

	if err := tf.EnsureStateDir(fwdStatePath); err != nil {
		return nil, err
	}
	if err := tf.WriteBackendOverride(fwdWorkDir, fwdStatePath); err != nil {
		return nil, err
	}
	defer tf.RemoveBackendOverride(fwdWorkDir)

	fwdVars := map[string]string{
		"hub_account_id":      hubAccountID,
		"hub_region":          "us-east-1", // EventBridge is global — hub region
		"spoke_alias":         spoke.Alias,
		"forwarding_role_name": ForwardingRoleName,
	}

	fwdRes, err := runner.ApplyWithVars(ctx, fwdWorkDir, fwdVars, dryRun)
	if err != nil {
		return nil, fmt.Errorf("deploy forwarding-role in spoke %s: %w", spoke.Alias, err)
	}
	if !dryRun {
		result.ForwardingRoleARN = fwdRes.Outputs["forwarding_role_arn"]
	}

	return result, nil
}

// DestroyForSpoke removes both IAM roles from a spoke via terraform destroy.
func DestroyForSpoke(
	ctx context.Context,
	spoke config.SpokeAccount,
	runner *tf.Runner,
	templatesDir, mirageDir string,
	dryRun bool,
) error {
	// Destroy deployment role.
	deployWorkDir := filepath.Join(templatesDir, "spoke-deployment-role")
	deployStatePath := tf.StatePath(mirageDir, "roles", spoke.Alias, "deployment-role")
	if !tf.StateExists(deployStatePath) {
		fmt.Printf("  [skip] deployment-role: no state found for %s\n", spoke.Alias)
	} else {
		if err := tf.WriteBackendOverride(deployWorkDir, deployStatePath); err != nil {
			return err
		}
		defer tf.RemoveBackendOverride(deployWorkDir)
		if _, err := runner.DestroyWithVars(ctx, deployWorkDir, map[string]string{"spoke_alias": spoke.Alias}, dryRun); err != nil {
			return fmt.Errorf("destroy deployment-role for %s: %w", spoke.Alias, err)
		}
	}

	// Destroy forwarding role.
	fwdWorkDir := filepath.Join(templatesDir, "spoke-forwarding-role")
	fwdStatePath := tf.StatePath(mirageDir, "roles", spoke.Alias, "forwarding-role")
	if !tf.StateExists(fwdStatePath) {
		fmt.Printf("  [skip] forwarding-role: no state found for %s\n", spoke.Alias)
	} else {
		if err := tf.WriteBackendOverride(fwdWorkDir, fwdStatePath); err != nil {
			return err
		}
		defer tf.RemoveBackendOverride(fwdWorkDir)
		if _, err := runner.DestroyWithVars(ctx, fwdWorkDir, map[string]string{"spoke_alias": spoke.Alias}, dryRun); err != nil {
			return fmt.Errorf("destroy forwarding-role for %s: %w", spoke.Alias, err)
		}
	}
	return nil
}

// StatusResult holds the health of one spoke's roles.
type StatusResult struct {
	SpokeAlias        string
	SpokeID           string
	DeploymentRoleARN string
	ForwardingRoleARN string
	Assumable         bool
	PolicyOK          bool
	LastUsedDaysAgo   int
	Error             string
}

// CheckStatus verifies a spoke's roles are healthy using STS + IAM API calls.
func CheckStatus(ctx context.Context, stsClient *awssts.Client, iamClient *iam.Client, spoke config.SpokeAccount) *StatusResult {
	status := &StatusResult{
		SpokeAlias:        spoke.Alias,
		SpokeID:           spoke.ID,
		DeploymentRoleARN: spoke.DeploymentRoleARN,
		ForwardingRoleARN: spoke.ForwardingRoleARN,
	}

	if spoke.DeploymentRoleARN == "" {
		status.Error = "no role ARN (run: mirage roles deploy --spoke " + spoke.Alias + ")"
		return status
	}

	// Try AssumeRole with ExternalId.
	_, err := stsClient.AssumeRole(ctx, &awssts.AssumeRoleInput{
		RoleArn:         aws.String(spoke.DeploymentRoleARN),
		RoleSessionName: aws.String("mirage-status-check"),
		ExternalId:      aws.String(ExternalID(spoke.Alias)),
		DurationSeconds: aws.Int32(900),
	})
	if err != nil {
		status.Assumable = false
		status.Error = "AssumeRole failed: " + cleanAWSError(err)
		return status
	}
	status.Assumable = true

	// Get last-used date.
	roleName := roleNameFromARN(spoke.DeploymentRoleARN)
	if roleName != "" {
		roleOut, err := iamClient.GetRole(ctx, &iam.GetRoleInput{
			RoleName: aws.String(roleName),
		})
		if err == nil && roleOut.Role != nil && roleOut.Role.RoleLastUsed != nil && roleOut.Role.RoleLastUsed.LastUsedDate != nil {
			// compute days ago — omitted for brevity, just mark as ok
			_ = roleOut.Role.RoleLastUsed.LastUsedDate
		}
	}

	// Check for attached policies.
	policiesOut, err := iamClient.ListAttachedRolePolicies(ctx, &iam.ListAttachedRolePoliciesInput{
		RoleName: aws.String(roleName),
	})
	inlineOut, ierr := iamClient.ListRolePolicies(ctx, &iam.ListRolePoliciesInput{
		RoleName: aws.String(roleName),
	})
	hasPolicies := (err == nil && len(policiesOut.AttachedPolicies) > 0) ||
		(ierr == nil && len(inlineOut.PolicyNames) > 0)
	status.PolicyOK = hasPolicies

	if !hasPolicies {
		status.Error = "no IAM policies attached to deployment role"
	}

	return status
}

// ImportValidate validates a pre-existing role ARN is assumable.
// Returns an ImportResult with missing permissions (if any).
type ImportResult struct {
	SpokeAlias        string
	DeploymentRoleARN string
	ForwardingRoleARN string
	Assumable         bool
	PolicyOK          bool
	MissingActions    []string
}

func ImportValidate(ctx context.Context, stsClient *awssts.Client, iamClient *iam.Client, spoke config.SpokeAccount, deployARN, fwdARN string) (*ImportResult, error) {
	result := &ImportResult{
		SpokeAlias:        spoke.Alias,
		DeploymentRoleARN: deployARN,
		ForwardingRoleARN: fwdARN,
	}

	// Validate AssumeRole works.
	_, err := stsClient.AssumeRole(ctx, &awssts.AssumeRoleInput{
		RoleArn:         aws.String(deployARN),
		RoleSessionName: aws.String("mirage-import-validation"),
		ExternalId:      aws.String(ExternalID(spoke.Alias)),
		DurationSeconds: aws.Int32(900),
	})
	if err != nil {
		return nil, fmt.Errorf(
			"cannot assume role %s:\n  %s\n\n"+
				"Fix: ensure the role trust policy allows:\n"+
				"  Principal: arn:aws:iam::<hub-account-id>:root\n"+
				"  Condition: sts:ExternalId = %s",
			deployARN, cleanAWSError(err), ExternalID(spoke.Alias))
	}
	result.Assumable = true

	// Check for at minimum one attached or inline policy.
	roleName := roleNameFromARN(deployARN)
	pOut, _ := iamClient.ListAttachedRolePolicies(ctx, &iam.ListAttachedRolePoliciesInput{
		RoleName: aws.String(roleName),
	})
	iOut, _ := iamClient.ListRolePolicies(ctx, &iam.ListRolePoliciesInput{
		RoleName: aws.String(roleName),
	})

	hasPolicies := (pOut != nil && len(pOut.AttachedPolicies) > 0) ||
		(iOut != nil && len(iOut.PolicyNames) > 0)

	if !hasPolicies {
		result.MissingActions = []string{"NO_POLICIES_ATTACHED"}
	}
	result.PolicyOK = hasPolicies
	return result, nil
}

// ExportTerraform returns a standalone .tf file for spoke admins to apply.
func ExportTerraform(hubAccountID string, spoke config.SpokeAccount) string {
	extID := ExternalID(spoke.Alias)
	return fmt.Sprintf(`# Mirage cross-account roles
# Spoke: %s (%s)
# Generated by: mirage roles export-template --spoke %s --format terraform
#
# Instructions for spoke admin:
#   1. Apply this in the spoke account (%s):
#      terraform init && terraform apply
#   2. Note the output ARNs
#   3. In the hub account, run:
#      mirage roles import %s \
#        --role-arn <deployment_role_arn> \
#        --forwarding-role-arn <forwarding_role_arn>

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

# --- Deployment Role (hub assumes this to deploy deception resources) ---
resource "aws_iam_role" "mirage_deployment" {
  name        = "mirage-deployment-role"
  description = "Mirage CLI: assumed by hub to deploy deception resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::%s:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = "%s" } }
    }]
  })
  tags = { ManagedBy = "mirage", SpokeAlias = "%s" }
}

resource "aws_iam_role_policy" "mirage_deployment_permissions" {
  name = "mirage-deception-deployment"
  role = aws_iam_role.mirage_deployment.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*","iam:*","secretsmanager:*","ssm:*","lambda:*","dynamodb:*","sqs:*","sns:*","logs:*","kms:*","ecr:*","events:*","cloudformation:*","ec2:*"]
      Resource = "*"
    }]
  })
}

# --- Forwarding Role (EventBridge uses this to forward events to hub bus) ---
resource "aws_iam_role" "mirage_forwarding" {
  name        = "mirage-forwarding-role"
  description = "Mirage CLI: EventBridge event forwarding to hub"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { ManagedBy = "mirage", SpokeAlias = "%s" }
}

output "deployment_role_arn" { value = aws_iam_role.mirage_deployment.arn }
output "forwarding_role_arn"  { value = aws_iam_role.mirage_forwarding.arn }
`, spoke.Alias, spoke.ID, spoke.Alias, spoke.ID, spoke.Alias,
		hubAccountID, extID, spoke.Alias, spoke.Alias)
}

// ExportCloudFormation returns a CloudFormation YAML template.
func ExportCloudFormation(hubAccountID string, spoke config.SpokeAccount) string {
	extID := ExternalID(spoke.Alias)
	return fmt.Sprintf(`# Mirage cross-account roles - CloudFormation
# Spoke: %s (%s)
AWSTemplateFormatVersion: '2010-09-09'
Description: Mirage CLI cross-account deception roles

Resources:
  MirageDeploymentRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: mirage-deployment-role
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: 'arn:aws:iam::%s:root'
            Action: 'sts:AssumeRole'
            Condition:
              StringEquals:
                'sts:ExternalId': '%s'
      Policies:
        - PolicyName: MirageDeceptionDeployment
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: ['s3:*','iam:*','secretsmanager:*','ssm:*','lambda:*','dynamodb:*','sqs:*','sns:*','logs:*','kms:*','ecr:*','events:*','cloudformation:*','ec2:*']
                Resource: '*'

  MirageForwardingRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: mirage-forwarding-role
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: events.amazonaws.com
            Action: 'sts:AssumeRole'

Outputs:
  DeploymentRoleArn:
    Value: !GetAtt MirageDeploymentRole.Arn
  ForwardingRoleArn:
    Value: !GetAtt MirageForwardingRole.Arn
`, spoke.Alias, spoke.ID, hubAccountID, extID)
}

// ─── Helpers ────────────────────────────────────────────────────────────────

// roleNameFromARN extracts the name from an IAM role ARN.
func roleNameFromARN(arn string) string {
	parts := strings.Split(arn, "/")
	if len(parts) < 2 {
		return ""
	}
	return parts[len(parts)-1]
}

// cleanAWSError extracts the human-readable part from an AWS SDK error.
func cleanAWSError(err error) string {
	if err == nil {
		return ""
	}
	msg := err.Error()
	// AWS SDK v2 errors often have "operation error ...: ...: <actual message>"
	if idx := strings.LastIndex(msg, ": "); idx != -1 {
		return strings.TrimSpace(msg[idx+2:])
	}
	return msg
}
