package awsctx

import (
	"fmt"

	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/pkg/models"
)

// ClassifyAccount compares the current identity's account ID against the
// mirage config and returns whether this is the hub, a spoke, or unknown.
func ClassifyAccount(identity *models.Identity, cfg *config.Config) models.AccountRole {
	if identity.AccountID == cfg.Accounts.Hub.ID {
		return models.RoleHub
	}
	for _, spoke := range cfg.Accounts.Spokes {
		if identity.AccountID == spoke.ID {
			return models.RoleSpoke
		}
	}
	return models.RoleUnknown
}

// SpokeAlias returns the alias for the current account if it's a spoke.
// Returns empty string if not a spoke.
func SpokeAlias(identity *models.Identity, cfg *config.Config) string {
	for _, spoke := range cfg.Accounts.Spokes {
		if identity.AccountID == spoke.ID {
			return spoke.Alias
		}
	}
	return ""
}

// RoleDescription returns a human-readable description of the account role.
func RoleDescription(role models.AccountRole) string {
	switch role {
	case models.RoleHub:
		return "hub (monitoring + management)"
	case models.RoleSpoke:
		return "spoke (deception target)"
	default:
		return "unknown (not in config)"
	}
}

// ClassifyError formats a helpful error message when the account is unknown.
func ClassifyError(identity *models.Identity, cfg *config.Config) error {
	return fmt.Errorf(
		"account %s is not registered in mirage config\n"+
			"  Current principal: %s\n"+
			"  Hub account:       %s\n"+
			"  Spoke accounts:    %v\n\n"+
			"Fix: run `mirage init` to register this account, or switch AWS profile",
		identity.AccountID,
		identity.ARN,
		cfg.Accounts.Hub.ID,
		spokeIDs(cfg),
	)
}

func spokeIDs(cfg *config.Config) []string {
	ids := make([]string, len(cfg.Accounts.Spokes))
	for i, s := range cfg.Accounts.Spokes {
		ids[i] = fmt.Sprintf("%s (%s)", s.ID, s.Alias)
	}
	return ids
}
