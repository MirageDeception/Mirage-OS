package awsctx

import (
	"context"
	"fmt"

	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/pkg/models"
)

// GuardFunc is the signature for commands that need account-role enforcement.
// Use as Cobra's PreRunE to enforce before any work begins.
type GuardFunc func(ctx context.Context, identity *models.Identity, cfg *config.Config) error

// RequireHub returns a GuardFunc that fails if the current account is not the hub.
// Use this for: monitor deploy, monitor destroy, monitor authorize, roles deploy (hub-side).
func RequireHub(region, profile string) GuardFunc {
	return func(ctx context.Context, identity *models.Identity, cfg *config.Config) error {
		role := ClassifyAccount(identity, cfg)
		if role == models.RoleHub {
			return nil
		}
		return fmt.Errorf(
			"❌ Account-role mismatch\n\n"+
				"  This command requires the HUB account (%s).\n"+
				"  Current account: %s (role: %s)\n\n"+
				"Fix: switch to the hub AWS profile:\n"+
				"  export AWS_PROFILE=<hub-profile>  or\n"+
				"  mirage --profile <hub-profile> <command>",
			cfg.Accounts.Hub.ID,
			identity.AccountID,
			RoleDescription(role),
		)
	}
}

// RequireSpoke returns a GuardFunc that fails if the current account is not a spoke.
// Use this for: scenario deploy, scenario destroy, scenario abuse, monitor forwarding.
func RequireSpoke(region, profile string) GuardFunc {
	return func(ctx context.Context, identity *models.Identity, cfg *config.Config) error {
		role := ClassifyAccount(identity, cfg)
		if role == models.RoleSpoke {
			return nil
		}
		spokeList := ""
		for _, s := range cfg.Accounts.Spokes {
			spokeList += fmt.Sprintf("  - %s (%s)\n", s.Alias, s.ID)
		}
		return fmt.Errorf(
			"❌ Account-role mismatch\n\n"+
				"  This command requires a SPOKE account.\n"+
				"  Current account: %s (role: %s)\n\n"+
				"Registered spokes:\n%s\n"+
				"Fix: switch to a spoke AWS profile:\n"+
				"  export AWS_PROFILE=<spoke-profile>  or\n"+
				"  mirage --profile <spoke-profile> <command>",
			identity.AccountID,
			RoleDescription(role),
			spokeList,
		)
	}
}

// RequireKnown returns a GuardFunc that fails if the account is not in config at all.
// Use for commands that work in either hub or spoke, but not unknown accounts.
func RequireKnown(region, profile string) GuardFunc {
	return func(ctx context.Context, identity *models.Identity, cfg *config.Config) error {
		role := ClassifyAccount(identity, cfg)
		if role != models.RoleUnknown {
			return nil
		}
		return ClassifyError(identity, cfg)
	}
}
