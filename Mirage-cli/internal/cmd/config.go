package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"
	"github.com/mirage-security/mirage/internal/config"
	"gopkg.in/yaml.v3"
)

func newConfigCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "config",
		Short: "View and modify mirage configuration",
	}
	cmd.AddCommand(newConfigShowCmd())
	cmd.AddCommand(newConfigSetCmd())
	return cmd
}

func newConfigShowCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "show",
		Short: "Print the current configuration",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if GlobalJSON {
				data, err := json.MarshalIndent(cfg, "", "  ")
				if err != nil {
					return err
				}
				fmt.Println(string(data))
				return nil
			}

			// YAML output — human-friendly.
			data, err := yaml.Marshal(cfg)
			if err != nil {
				return err
			}
			color.Cyan("# ~/.mirage/config.yaml\n")
			fmt.Println(string(data))
			fmt.Printf("Config file: %s\n", config.ConfigPath())
			return nil
		},
	}
}

func newConfigSetCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "set <key> <value>",
		Short: "Update a config value by dot-notation key",
		Long: `Update a single config value.

Examples:
  mirage config set naming.prefix prod
  mirage config set region eu-west-1
  mirage config set catalogue.backend dynamodb`,
		Args: cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			key, value := args[0], args[1]

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			if err := applyConfigKey(cfg, key, value); err != nil {
				return err
			}

			if err := config.Save(cfg); err != nil {
				return err
			}

			color.Green("✓ Set %s = %s", key, value)
			return nil
		},
	}
}

// applyConfigKey applies a dot-notation key to the config struct.
// Supports a fixed set of common keys. Extend as needed.
func applyConfigKey(cfg *config.Config, key, value string) error {
	switch strings.ToLower(key) {
	case "region":
		cfg.Region = value
	case "cloud":
		cfg.Cloud = value
	case "naming.prefix":
		cfg.Naming.Prefix = value
	case "naming.separator":
		cfg.Naming.Separator = value
	case "catalogue.backend":
		if value != "sqlite" && value != "dynamodb" {
			return fmt.Errorf("catalogue.backend must be 'sqlite' or 'dynamodb'")
		}
		cfg.Catalogue.Backend = value
	case "monitoring.event_bus_name":
		cfg.Monitoring.EventBusName = value
	case "operational.auto_verify_after_deploy":
		cfg.Operational.AutoVerifyAfterDeploy = value == "true"
	default:
		return fmt.Errorf("unknown config key %q\n\nSupported keys: region, cloud, naming.prefix, naming.separator, catalogue.backend, monitoring.event_bus_name, operational.auto_verify_after_deploy", key)
	}
	return nil
}
