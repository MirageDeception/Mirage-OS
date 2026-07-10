package cmd

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/fatih/color"
	"github.com/spf13/cobra"

	awsctx "github.com/mirage-security/mirage/internal/awsctx"
	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/roles"
	"github.com/mirage-security/mirage/internal/tf"
)

func newRolesCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "roles",
		Short: "Manage cross-account IAM roles for hub→spoke access",
		Long: `Deploy, import, validate, and export cross-account IAM roles.

Two roles are needed in each spoke account:
  1. mirage-deployment-role   — hub assumes this to deploy decoys (with ExternalId)
  2. mirage-forwarding-role   — EventBridge uses this to forward events to hub bus

Deploy order:
  roles deploy --all-spokes   (or roles import if you create roles externally)
  ↓
  monitor deploy              (hub side)
  ↓
  monitor forwarding          (spoke side)
  ↓
  scenario deploy --all       (spoke side)`,
	}

	cmd.AddCommand(newRolesDeployCmd())
	cmd.AddCommand(newRolesImportCmd())
	cmd.AddCommand(newRolesStatusCmd())
	cmd.AddCommand(newRolesDestroyCmd())
	cmd.AddCommand(newRolesExportCmd())
	return cmd
}

// ── roles deploy ─────────────────────────────────────────────────────────────

func newRolesDeployCmd() *cobra.Command {
	var (
		flagSpoke     string
		flagAllSpokes bool
	)

	cmd := &cobra.Command{
		Use:   "deploy",
		Short: "Deploy cross-account IAM roles into spoke account(s)",
		Long: `Creates mirage-deployment-role + mirage-forwarding-role in spoke(s).

  Guard: must run this from the HUB account.

  For each spoke, mirage:
    1. Generates Terraform variables (trust policy + permissions)
    2. Applies templates/roles/spoke-deployment-role/
    3. Applies templates/roles/spoke-forwarding-role/
    4. Writes ARNs back to ~/.mirage/config.yaml
    5. Marks spoke.roles_deployed = true`,
		Example: `  # Deploy to all spokes
  mirage roles deploy --all-spokes

  # Deploy to one spoke
  mirage roles deploy --spoke prod

  # Preview without deploying
  mirage roles deploy --all-spokes --dry-run`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			// Resolve identity and enforce hub guard.
			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			if err := awsctx.RequireHub(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			// Determine target spokes.
			var targetSpokes []config.SpokeAccount
			switch {
			case flagAllSpokes:
				targetSpokes = cfg.Accounts.Spokes
			case flagSpoke != "":
				s, err := cfg.GetSpoke(flagSpoke)
				if err != nil {
					return err
				}
				targetSpokes = []config.SpokeAccount{*s}
			default:
				return fmt.Errorf("specify --spoke <alias> or --all-spokes")
			}

			if len(targetSpokes) == 0 {
				return fmt.Errorf("no spokes configured — run `mirage init` to add spokes")
			}

			// Locate templates directory.
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}
			templatesDir := filepath.Join(repoRoot, "Mirage-cli", "templates", "roles")
			mirageDir := config.MirageDir()

			runner := tf.NewRunner(GlobalVerbose)

			if err := tf.CheckInstalled(); err != nil {
				return err
			}

			// Check terraform binary exists.
			bold := color.New(color.Bold)
			green := color.New(color.FgGreen)
			yellow := color.New(color.FgYellow)

			if GlobalDryRun {
				yellow.Println("DRY RUN — showing plan only, no changes will be made")
			}

			fmt.Printf("\nDeploying IAM roles into %d spoke(s)...\n\n", len(targetSpokes))

			var errs []string
			for _, spoke := range targetSpokes {
				bold.Printf("  ▶ Spoke: %s (%s)\n", spoke.Alias, spoke.ID)

				result, err := roles.DeployForSpoke(ctx, cfg.Accounts.Hub.ID, spoke, runner, templatesDir, mirageDir, GlobalDryRun)
				if err != nil {
					color.Red("    ✗ Failed: %s\n", err)
					errs = append(errs, fmt.Sprintf("%s: %s", spoke.Alias, err))
					continue
				}

				if GlobalDryRun {
					yellow.Printf("    ✓ Plan complete (dry-run)\n")
					continue
				}

				// Update config with deployed ARNs.
				for i, s := range cfg.Accounts.Spokes {
					if s.Alias == spoke.Alias {
						cfg.Accounts.Spokes[i].DeploymentRoleARN = result.DeploymentRoleARN
						cfg.Accounts.Spokes[i].ForwardingRoleARN = result.ForwardingRoleARN
						cfg.Accounts.Spokes[i].RolesDeployed = true
					}
				}

				green.Printf("    ✓ Deployment role: %s\n", result.DeploymentRoleARN)
				green.Printf("    ✓ Forwarding role:  %s\n", result.ForwardingRoleARN)
			}

			if !GlobalDryRun {
				if err := config.Save(cfg); err != nil {
					return fmt.Errorf("save config with role ARNs: %w", err)
				}
				green.Println("\n✓ Config updated with role ARNs")
			}

			if len(errs) > 0 {
				return fmt.Errorf("%d spoke(s) failed:\n  %s", len(errs), strings.Join(errs, "\n  "))
			}

			if !GlobalDryRun {
				fmt.Println("\nNext steps:")
				fmt.Println("  1. mirage monitor deploy           # (hub account) deploy detection pipeline")
				fmt.Println("  2. mirage monitor forwarding       # (spoke account) deploy event forwarding")
				fmt.Println("  3. mirage scenario deploy --all    # (spoke account) deploy decoy resources")
			}
			return nil
		},
	}

	cmd.Flags().StringVar(&flagSpoke, "spoke", "", "Deploy roles into a single spoke by alias")
	cmd.Flags().BoolVar(&flagAllSpokes, "all-spokes", false, "Deploy roles into all configured spokes")
	return cmd
}

// ── roles import ─────────────────────────────────────────────────────────────

func newRolesImportCmd() *cobra.Command {
	var (
		flagRoleARN string
		flagFwdARN  string
	)

	cmd := &cobra.Command{
		Use:   "import <spoke-alias>",
		Short: "Import pre-existing IAM roles (no Terraform needed)",
		Long: `Use when your platform/IAM team created the roles externally.

  Validates:
    - Role is assumable from the hub account (sts:AssumeRole + ExternalId)
    - Role has at least one policy attached
    - If permissions appear insufficient: prints required policy JSON

  Writes ARNs to ~/.mirage/config.yaml.`,
		Example: `  mirage roles import prod \
    --role-arn arn:aws:iam::123456789012:role/mirage-deployment-role \
    --forwarding-role-arn arn:aws:iam::123456789012:role/mirage-forwarding-role`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()
			spokeAlias := args[0]

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			spoke, err := cfg.GetSpoke(spokeAlias)
			if err != nil {
				return err
			}

			// Build AWS clients.
			awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			stsClient := sts.NewFromConfig(awsCfg)
			iamClient := iam.NewFromConfig(awsCfg)

			fmt.Printf("Validating role for spoke %s...\n", spokeAlias)

			result, err := roles.ImportValidate(ctx, stsClient, iamClient, *spoke, flagRoleARN, flagFwdARN)
			if err != nil {
				return err
			}

			green := color.New(color.FgGreen)
			yellow := color.New(color.FgYellow)

			if result.Assumable {
				green.Printf("  ✓ Role is assumable from hub (ExternalId: %s)\n", roles.ExternalID(spokeAlias))
			}

			if !result.PolicyOK {
				yellow.Println("  ⚠ Role has no attached policies — you must attach the deception permissions.")
				fmt.Println("\nRequired IAM policy to attach:")
				fmt.Println(`  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:*","iam:*","secretsmanager:*","ssm:*","lambda:*",
                 "dynamodb:*","sqs:*","sns:*","logs:*","kms:*",
                 "ecr:*","events:*","cloudformation:*","ec2:*"],
      "Resource": "*"
    }]
  }`)
			} else {
				green.Println("  ✓ Role has policies attached")
			}

			// Write to config.
			for i, s := range cfg.Accounts.Spokes {
				if s.Alias == spokeAlias {
					cfg.Accounts.Spokes[i].DeploymentRoleARN = result.DeploymentRoleARN
					if result.ForwardingRoleARN != "" {
						cfg.Accounts.Spokes[i].ForwardingRoleARN = result.ForwardingRoleARN
					}
					cfg.Accounts.Spokes[i].RolesDeployed = true
				}
			}

			if err := config.Save(cfg); err != nil {
				return fmt.Errorf("save config: %w", err)
			}

			green.Printf("\n✓ Imported role ARN for spoke %s\n", spokeAlias)
			return nil
		},
	}

	cmd.Flags().StringVar(&flagRoleARN, "role-arn", "", "ARN of the deployment role to import (required)")
	cmd.Flags().StringVar(&flagFwdARN, "forwarding-role-arn", "", "ARN of the forwarding role to import")
	_ = cmd.MarkFlagRequired("role-arn")
	return cmd
}

// ── roles status ─────────────────────────────────────────────────────────────

func newRolesStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Check health of cross-account roles for all spokes",
		Long: `Tests each spoke's roles:
  - Attempts sts:AssumeRole with ExternalId
  - Verifies policy is attached
  - Reports last-used date (stale if >90 days)

Prints a status matrix: spoke | assumable | policy_ok | last_used | error`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if len(cfg.Accounts.Spokes) == 0 {
				return fmt.Errorf("no spokes configured")
			}

			awsCfg, err := awsctx.NewAWSConfig(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			stsClient := sts.NewFromConfig(awsCfg)
			iamClient := iam.NewFromConfig(awsCfg)

			fmt.Printf("\n  Hub: %s (%s)\n\n", cfg.Accounts.Hub.Alias, cfg.Accounts.Hub.ID)

			green := color.New(color.FgGreen)
			red := color.New(color.FgRed)

			// Header.
			fmt.Printf("  %-15s %-15s %-12s %-12s  %s\n",
				"SPOKE", "ACCOUNT", "ASSUMABLE", "POLICY OK", "ERROR")
			fmt.Println("  " + strings.Repeat("─", 75))

			for _, spoke := range cfg.Accounts.Spokes {
				status := roles.CheckStatus(ctx, stsClient, iamClient, spoke)

				assumable := red.Sprint("✗")
				if status.Assumable {
					assumable = green.Sprint("✓")
				}
				policyOK := red.Sprint("✗")
				if status.PolicyOK {
					policyOK = green.Sprint("✓")
				}
				errMsg := status.Error
				if len(errMsg) > 40 {
					errMsg = errMsg[:37] + "..."
				}

				fmt.Printf("  %-15s %-15s %-12s %-12s  %s\n",
					spoke.Alias, spoke.ID, assumable, policyOK, errMsg)
			}
			return nil
		},
	}
}

// ── roles destroy ─────────────────────────────────────────────────────────────

func newRolesDestroyCmd() *cobra.Command {
	var flagSpoke string

	cmd := &cobra.Command{
		Use:   "destroy",
		Short: "Remove cross-account IAM roles from a spoke account",
		Long: `Destroys mirage-deployment-role and mirage-forwarding-role in the spoke.

  Guard: must run from the HUB account.
  Requires double confirmation (type the spoke alias to confirm).

  After destroying roles, any deployed scenarios become unmanageable.
  Always destroy scenarios first: mirage scenario destroy --all`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if flagSpoke == "" {
				return fmt.Errorf("--spoke <alias> is required")
			}

			spoke, err := cfg.GetSpoke(flagSpoke)
			if err != nil {
				return err
			}

			// Hub guard.
			identity, err := awsctx.GetIdentity(ctx, cfg.Region, GlobalProfile)
			if err != nil {
				return err
			}
			if err := awsctx.RequireHub(cfg.Region, GlobalProfile)(ctx, identity, cfg); err != nil {
				return err
			}

			// Double confirm.
			if !GlobalYes {
				color.Red("\n⚠ WARNING: Destroying roles will remove all mirage management access to spoke %s (%s)", spoke.Alias, spoke.ID)
				fmt.Printf("\nType the spoke alias to confirm [%s]: ", spoke.Alias)
				reader := bufio.NewReader(os.Stdin)
				confirm, _ := reader.ReadString('\n')
				confirm = strings.TrimSpace(confirm)
				if confirm != spoke.Alias {
					return fmt.Errorf("confirmation mismatch — aborting")
				}
			}

			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}
			templatesDir := filepath.Join(repoRoot, "Mirage-cli", "templates", "roles")
			mirageDir := config.MirageDir()
			runner := tf.NewRunner(GlobalVerbose)

			fmt.Printf("\nDestroying roles for spoke %s...\n", spoke.Alias)
			if err := roles.DestroyForSpoke(ctx, *spoke, runner, templatesDir, mirageDir, GlobalDryRun); err != nil {
				return err
			}

			if !GlobalDryRun {
				// Clear ARNs from config.
				for i, s := range cfg.Accounts.Spokes {
					if s.Alias == spoke.Alias {
						cfg.Accounts.Spokes[i].DeploymentRoleARN = ""
						cfg.Accounts.Spokes[i].ForwardingRoleARN = ""
						cfg.Accounts.Spokes[i].RolesDeployed = false
					}
				}
				if err := config.Save(cfg); err != nil {
					return fmt.Errorf("update config: %w", err)
				}
				color.Green("✓ Roles destroyed and config updated")
			}
			return nil
		},
	}

	cmd.Flags().StringVar(&flagSpoke, "spoke", "", "Spoke alias to destroy roles from (required)")
	return cmd
}

// ── roles export-template ────────────────────────────────────────────────────

func newRolesExportCmd() *cobra.Command {
	var (
		flagSpoke  string
		flagFormat string
		flagOutput string
	)

	cmd := &cobra.Command{
		Use:   "export-template",
		Short: "Generate a self-contained IAM role template for spoke admins",
		Long: `Generates a Terraform (.tf) or CloudFormation (.yaml) template
that a spoke administrator can apply independently.

This is the recommended workflow when you don't have direct spoke access:
  1. Run: mirage roles export-template --spoke prod --format terraform
  2. Send the output file to the spoke admin
  3. Spoke admin applies it
  4. Spoke admin sends you the output ARNs
  5. Run: mirage roles import prod --role-arn <arn>`,
		Example: `  mirage roles export-template --spoke prod --format terraform
  mirage roles export-template --spoke prod --format cloudformation -o roles.yaml`,
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if flagSpoke == "" {
				return fmt.Errorf("--spoke <alias> is required")
			}

			spoke, err := cfg.GetSpoke(flagSpoke)
			if err != nil {
				return err
			}

			var content string
			switch strings.ToLower(flagFormat) {
			case "terraform", "tf":
				content = roles.ExportTerraform(cfg.Accounts.Hub.ID, *spoke)
				if flagOutput == "" {
					flagOutput = fmt.Sprintf("mirage-roles-%s.tf", spoke.Alias)
				}
			case "cloudformation", "cfn", "cf":
				content = roles.ExportCloudFormation(cfg.Accounts.Hub.ID, *spoke)
				if flagOutput == "" {
					flagOutput = fmt.Sprintf("mirage-roles-%s.yaml", spoke.Alias)
				}
			default:
				return fmt.Errorf("unknown format %q — use 'terraform' or 'cloudformation'", flagFormat)
			}

			if err := os.WriteFile(flagOutput, []byte(content), 0600); err != nil {
				return fmt.Errorf("write template: %w", err)
			}

			color.Green("✓ Template written to %s", flagOutput)
			fmt.Printf("\nInstructions for %s spoke admin:\n", spoke.Alias)
			fmt.Printf("  1. Apply the template in account %s\n", spoke.ID)
			if strings.HasPrefix(flagFormat, "terraform") || flagFormat == "tf" {
				fmt.Printf("     cd <dir> && terraform init && terraform apply\n")
			} else {
				fmt.Printf("     aws cloudformation create-stack --stack-name mirage-roles --template-body file://%s\n", flagOutput)
			}
			fmt.Printf("  2. Send you the output ARNs\n")
			fmt.Printf("  3. You import them:\n")
			fmt.Printf("     mirage roles import %s --role-arn <deployment_role_arn>\n", spoke.Alias)
			return nil
		},
	}

	cmd.Flags().StringVar(&flagSpoke, "spoke", "", "Spoke alias to generate template for (required)")
	cmd.Flags().StringVar(&flagFormat, "format", "terraform", "Output format: terraform | cloudformation")
	cmd.Flags().StringVarP(&flagOutput, "output", "o", "", "Output file path (default: mirage-roles-<spoke>.<ext>)")
	return cmd
}

// ── helpers ─────────────────────────────────────────────────────────────────

// findRepoRoot walks up from the binary's working directory to find the repo root
// (identified by the presence of a go.mod with the mirage module path).
func findRepoRoot() (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}

	dir := cwd
	for {
		gomod := filepath.Join(dir, "go.mod")
		if data, err := os.ReadFile(gomod); err == nil {
			if strings.Contains(string(data), "github.com/mirage-security/mirage") {
				// Mirage-cli is the repo root for Go — parent is Mirage-OS root
				parent := filepath.Dir(dir)
				return parent, nil
			}
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break // reached filesystem root
		}
		dir = parent
	}

	// Fallback: check env var MIRAGE_REPO_ROOT.
	if root := os.Getenv("MIRAGE_REPO_ROOT"); root != "" {
		return root, nil
	}

	return "", fmt.Errorf(
		"cannot locate Mirage-OS repo root\n" +
			"Fix: set MIRAGE_REPO_ROOT=/path/to/Mirage-OS or run mirage from within the repository",
	)
}
