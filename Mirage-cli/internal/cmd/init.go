package cmd

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"
	awsctx "github.com/mirage-security/mirage/internal/awsctx"
	"github.com/mirage-security/mirage/internal/config"
)

func newInitCmd() *cobra.Command {
	var (
		flagHub      string
		flagSpokes   []string
		flagEmails   []string
		flagPrefix   string
		flagCatalogue string
		flagOrg      bool
		flagNoOrg    bool
	)

	cmd := &cobra.Command{
		Use:   "init",
		Short: "Bootstrap mirage: configure accounts, naming, and alerts",
		Long: `Bootstrap mirage for your environment.

Walks through:
  1. AWS auth verification
  2. Organization detection  
  3. Hub + spoke account enrollment
  4. Resource naming conventions
  5. Catalogue backend selection
  6. Alert email configuration

Saves config to ~/.mirage/config.yaml (mode 0600).

Non-interactive mode (CI/scripting):
  mirage init --hub <account-id> --spoke <alias:account-id> --email <addr> --prefix <p>`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			// Determine if non-interactive (all required flags provided).
			nonInteractive := flagHub != "" && len(flagSpokes) > 0

			cfg := config.Defaults()

			if nonInteractive {
				return runInitNonInteractive(ctx, cfg, flagHub, flagSpokes, flagEmails, flagPrefix, flagCatalogue)
			}
			return runInitInteractive(ctx, cfg)
		},
	}

	cmd.Flags().StringVar(&flagHub, "hub", "", "Hub account ID (e.g. 123456789012)")
	cmd.Flags().StringArrayVar(&flagSpokes, "spoke", nil, "Spoke account in alias:account-id format (repeatable)")
	cmd.Flags().StringArrayVar(&flagEmails, "email", nil, "Alert email address (repeatable)")
	cmd.Flags().StringVar(&flagPrefix, "prefix", "corp", "Resource naming prefix")
	cmd.Flags().StringVar(&flagCatalogue, "catalogue", "sqlite", "Catalogue backend: sqlite | dynamodb")
	cmd.Flags().BoolVar(&flagOrg, "org", false, "This is an AWS Organizations account")
	cmd.Flags().BoolVar(&flagNoOrg, "no-org", false, "Standalone (not Organizations) hub")
	return cmd
}

// runInitInteractive walks the user through interactive prompts.
func runInitInteractive(ctx context.Context, cfg *config.Config) error {
	bold := color.New(color.Bold)
	cyan := color.New(color.FgCyan)
	green := color.New(color.FgGreen)
	yellow := color.New(color.FgYellow)

	bold.Println("\n🛡  Welcome to Mirage — Cloud Deception Infrastructure")
	fmt.Println(strings.Repeat("─", 60))

	// Step 1: Cloud provider.
	cyan.Println("\n[1/6] Cloud Provider")
	fmt.Println("  Currently supported: AWS")
	fmt.Println("  Future: Azure, GCP, Kubernetes")
	cfg.Cloud = "aws"
	green.Println("  ✓ Cloud: AWS")

	// Step 2: Auth.
	cyan.Println("\n[2/6] AWS Authentication")
	fmt.Printf("  Verifying credentials (region: %s)...\n", cfg.Region)
	identity, err := awsctx.GetIdentity(ctx, GlobalRegion, GlobalProfile)
	if err != nil {
		return fmt.Errorf("auth failed: %w", err)
	}
	green.Printf("  ✓ Account: %s\n", identity.AccountID)
	fmt.Printf("  ✓ Principal: %s\n", identity.ARN)

	// Step 3: Hub account.
	cyan.Println("\n[3/6] Hub Account")
	fmt.Printf("  Current account %s — is this the HUB (monitoring + management) account?\n", identity.AccountID)
	if promptYesNo("  Use this account as hub? [Y/n]: ", true) {
		cfg.Accounts.Hub.ID = identity.AccountID
		cfg.Accounts.Hub.Alias = "security-hub"
	} else {
		cfg.Accounts.Hub.ID = promptString("  Enter hub account ID: ", "")
		cfg.Accounts.Hub.Alias = promptString("  Hub alias [security-hub]: ", "security-hub")
	}
	green.Printf("  ✓ Hub: %s (%s)\n", cfg.Accounts.Hub.Alias, cfg.Accounts.Hub.ID)

	// Step 4: Spoke accounts.
	cyan.Println("\n[4/6] Spoke Accounts")
	fmt.Println("  Spoke accounts host your deception resources (honeypots, lures, decoys).")
	for i := 1; ; i++ {
		spokeID := promptString(fmt.Sprintf("  Spoke %d account ID (or press Enter to finish): ", i), "")
		if spokeID == "" {
			break
		}
		alias := promptString(fmt.Sprintf("  Spoke %d alias [spoke-%d]: ", i, i), fmt.Sprintf("spoke-%d", i))
		env := promptString(fmt.Sprintf("  Spoke %d environment [production]: ", i), "production")
		cfg.Accounts.Spokes = append(cfg.Accounts.Spokes, config.SpokeAccount{
			ID:          spokeID,
			Alias:       alias,
			Environment: env,
		})
		green.Printf("  ✓ Added spoke: %s (%s)\n", alias, spokeID)
	}

	if len(cfg.Accounts.Spokes) == 0 {
		yellow.Println("  ⚠ No spokes configured. Add spokes later with `mirage config set` or re-run `mirage init`.")
	}

	// Step 5: Naming prefix.
	cyan.Println("\n[5/6] Resource Naming")
	fmt.Println("  Resources are named to blend with your real infrastructure.")
	fmt.Printf("  Pattern example: {prefix}-terraform-state-{suffix}\n")
	prefix := promptString("  Naming prefix [corp]: ", "corp")
	cfg.Naming.Prefix = prefix
	green.Printf("  ✓ Prefix: %s\n", prefix)
	fmt.Printf("  Example: %s-terraform-state-a3f9\n", prefix)

	// Step 6: Alert emails.
	cyan.Println("\n[6/6] Alert Emails")
	fmt.Println("  Emails to notify when a decoy resource is accessed.")
	for i := 1; ; i++ {
		email := promptString(fmt.Sprintf("  Email %d (or press Enter to finish): ", i), "")
		if email == "" {
			break
		}
		cfg.Alerts.Emails = append(cfg.Alerts.Emails, email)
		green.Printf("  ✓ Added: %s\n", email)
	}

	// Save config.
	if err := config.Save(cfg); err != nil {
		return fmt.Errorf("save config: %w", err)
	}

	fmt.Println()
	fmt.Println(strings.Repeat("─", 60))
	green.Println("✓ Config saved to ~/.mirage/config.yaml")
	fmt.Println()
	fmt.Println("Next steps:")
	fmt.Println("  1. mirage roles deploy --all-spokes    # deploy cross-account IAM roles")
	fmt.Println("  2. mirage monitor deploy               # deploy detection pipeline (hub)")
	fmt.Println("  3. mirage monitor forwarding           # deploy event forwarding (spoke)")
	fmt.Println("  4. mirage scenario deploy --all        # deploy all deception scenarios")
	fmt.Println()

	return nil
}

// runInitNonInteractive sets config values from flags and saves.
func runInitNonInteractive(ctx context.Context, cfg *config.Config, hub string, spokes, emails []string, prefix, catalogue string) error {
	identity, err := awsctx.GetIdentity(ctx, GlobalRegion, GlobalProfile)
	if err != nil {
		return fmt.Errorf("auth failed: %w", err)
	}
	_ = identity // validated

	cfg.Accounts.Hub.ID = hub
	cfg.Accounts.Hub.Alias = "security-hub"

	for _, s := range spokes {
		parts := strings.SplitN(s, ":", 2)
		if len(parts) != 2 {
			return fmt.Errorf("spoke format must be alias:account-id, got %q", s)
		}
		cfg.Accounts.Spokes = append(cfg.Accounts.Spokes, config.SpokeAccount{
			Alias: parts[0],
			ID:    parts[1],
		})
	}

	cfg.Alerts.Emails = emails
	if prefix != "" {
		cfg.Naming.Prefix = prefix
	}
	if catalogue != "" {
		cfg.Catalogue.Backend = catalogue
	}

	if err := config.Save(cfg); err != nil {
		return fmt.Errorf("save config: %w", err)
	}

	color.Green("✓ Config saved to ~/.mirage/config.yaml")
	return nil
}

// promptYesNo prompts the user and returns true for y/Y/yes/enter-with-default-true.
func promptYesNo(prompt string, defaultYes bool) bool {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print(prompt)
	answer, _ := reader.ReadString('\n')
	answer = strings.TrimSpace(strings.ToLower(answer))
	if answer == "" {
		return defaultYes
	}
	return answer == "y" || answer == "yes"
}

// promptString prompts for a string, returning defaultVal if empty.
func promptString(prompt, defaultVal string) string {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print(prompt)
	val, _ := reader.ReadString('\n')
	val = strings.TrimSpace(val)
	if val == "" {
		return defaultVal
	}
	return val
}
