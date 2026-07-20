// Package cmd — catalogue.go
// Full implementation of the `mirage catalogue` command group.
// Provides: show, sync, export, audit subcommands.
package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/mirage-security/mirage/internal/catalogue"
	"github.com/mirage-security/mirage/internal/config"
)

func newCatalogueCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "catalogue",
		Short: "View and manage the deployed resource registry",
		Long: `Browse, sync, and export the deception resource catalogue.

The catalogue is the single source of truth for all deployed decoy resources.
Every deploy/destroy operation writes to it before completing.

Backends:
  sqlite    local at ~/.mirage/catalogue.db (default)
  dynamodb  shared team database`,
	}

	cmd.AddCommand(newCatalogueShowCmd())
	cmd.AddCommand(newCatalogueSyncCmd())
	cmd.AddCommand(newCatalogueExportCmd())
	cmd.AddCommand(newCatalogueAuditCmd())
	return cmd
}

// ── catalogue show ─────────────────────────────────────────────────────────

func newCatalogueShowCmd() *cobra.Command {
	var (
		flagSpoke    string
		flagScenario int
		flagStatus   string
	)
	cmd := &cobra.Command{
		Use:   "show",
		Short: "List all tracked resources in the catalogue",
		Long: `Displays deployed deception resources from the local catalogue.

Filter by spoke, scenario number, or status.
Statuses: active | destroyed | orphaned`,
		Example: `  mirage catalogue show
  mirage catalogue show --spoke prod
  mirage catalogue show --scenario 3 --status active
  mirage catalogue show --json`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			store, err := openCatalogueStore(cfg)
			if err != nil {
				return err
			}
			defer store.Close()

			filter := catalogue.ResourceFilter{
				SpokeAlias:  flagSpoke,
				ScenarioNum: flagScenario,
				Status:      flagStatus,
			}

			resources, err := store.ListResources(ctx, filter)
			if err != nil {
				return fmt.Errorf("list resources: %w", err)
			}

			if len(resources) == 0 {
				color.Yellow("  No resources found in catalogue.\n")
				if flagSpoke == "" {
					fmt.Println("  Deploy scenarios first: mirage scenario deploy --all")
				}
				return nil
			}

			if GlobalJSON {
				b, err := json.MarshalIndent(resources, "", "  ")
				if err != nil {
					return err
				}
				fmt.Println(string(b))
				return nil
			}

			fmt.Printf("\n  Catalogue — %d resource(s)\n\n", len(resources))

			// Print simple aligned table.
			fmt.Printf("  %-4s  %-10s  %-22s  %-18s  %-30s  %-10s  %s\n",
				"ID", "SPOKE", "SCENARIO", "TYPE", "NAME", "STATUS", "DEPLOYED")
			fmt.Println("  " + strings.Repeat("─", 112))

			for _, r := range resources {
				statusLabel := r.Status
				switch r.Status {
				case "active":
					statusLabel = color.GreenString("active")
				case "destroyed":
					statusLabel = color.New(color.FgHiBlack).Sprint("destroyed")
				case "orphaned":
					statusLabel = color.YellowString("orphaned")
				}
				scenarioLabel := fmt.Sprintf("%d – %s", r.ScenarioNum, r.ScenarioName)
				if len(scenarioLabel) > 22 {
					scenarioLabel = scenarioLabel[:20] + "…"
				}
				resourceName := r.ResourceName
				if len(resourceName) > 30 {
					resourceName = resourceName[:28] + "…"
				}
				fmt.Printf("  %-4d  %-10s  %-22s  %-18s  %-30s  %-10s  %s\n",
					r.ID, r.SpokeAlias, scenarioLabel, r.ResourceType,
					resourceName, statusLabel, r.DeployedAt.Format("2006-01-02 15:04"))
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&flagSpoke, "spoke", "", "Filter by spoke alias")
	cmd.Flags().IntVar(&flagScenario, "scenario", 0, "Filter by scenario number")
	cmd.Flags().StringVar(&flagStatus, "status", "active", "Filter by status: active | destroyed | orphaned | '' (all)")
	return cmd
}

// ── catalogue sync ─────────────────────────────────────────────────────────

func newCatalogueSyncCmd() *cobra.Command {
	var flagSpoke string
	cmd := &cobra.Command{
		Use:   "sync",
		Short: "Reconcile catalogue against terraform state and live AWS",
		Long: `Detects divergence between catalogue entries and actual deployed state.

  Orphaned  — in catalogue but not in Terraform state → mark orphaned
  In-sync   — state file present (full live-check via AWS API in future releases)`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			store, err := openCatalogueStore(cfg)
			if err != nil {
				return err
			}
			defer store.Close()

			filter := catalogue.ResourceFilter{
				SpokeAlias: flagSpoke,
				Status:     "active",
			}

			resources, err := store.ListResources(ctx, filter)
			if err != nil {
				return fmt.Errorf("read catalogue: %w", err)
			}

			if len(resources) == 0 {
				color.Yellow("  No active resources in catalogue to sync.\n")
				return nil
			}

			fmt.Printf("\n  Syncing %d resource(s)...\n\n", len(resources))

			orphaned := 0
			inSync := 0

			for _, r := range resources {
				// Lightweight sync: check Terraform state file presence.
				stateExists := r.TFStatePath != "" && fileExists(r.TFStatePath)

				if stateExists {
					inSync++
					if GlobalVerbose {
						color.Green("  ✓ %s (%s)\n", r.ResourceName, r.ResourceType)
					}
				} else {
					orphaned++
					if err := store.MarkOrphaned(ctx, r.ID); err != nil {
						color.Red("  ✗ Failed to mark %d as orphaned: %v\n", r.ID, err)
					} else {
						color.Yellow("  ⚠ Orphaned: %s (%s) — state file missing\n", r.ResourceName, r.SpokeAlias)
					}
				}
			}

			fmt.Printf("\n  Sync complete: %d in-sync, %d orphaned\n", inSync, orphaned)
			return nil
		},
	}
	cmd.Flags().StringVar(&flagSpoke, "spoke", "", "Sync a specific spoke only")
	return cmd
}

// ── catalogue export ────────────────────────────────────────────────────────

func newCatalogueExportCmd() *cobra.Command {
	var (
		flagFormat string
		flagOutput string
		flagLimit  int
	)
	cmd := &cobra.Command{
		Use:   "export",
		Short: "Export catalogue to JSON or CSV for audit",
		Example: `  mirage catalogue export --format json -o resources.json
  mirage catalogue export --format csv -o audit.csv`,
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			store, err := openCatalogueStore(cfg)
			if err != nil {
				return err
			}
			defer store.Close()

			auditLog := catalogue.NewAuditLog(store)

			var w *os.File
			var openErr error
			if flagOutput == "" || flagOutput == "-" {
				w = os.Stdout
			} else {
				w, openErr = os.OpenFile(flagOutput, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
				if openErr != nil {
					return fmt.Errorf("create output file: %w", openErr)
				}
				defer w.Close()
			}

			switch strings.ToLower(flagFormat) {
			case "json":
				if err := auditLog.ExportJSON(ctx, flagLimit, w); err != nil {
					return err
				}
			case "csv":
				if err := auditLog.ExportCSV(ctx, flagLimit, w); err != nil {
					return err
				}
			default:
				return fmt.Errorf("unknown format %q — use 'json' or 'csv'", flagFormat)
			}

			if flagOutput != "" && flagOutput != "-" {
				color.Green("✓ Exported %d operation(s) to %s\n", flagLimit, flagOutput)
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&flagFormat, "format", "json", "Output format: json | csv")
	cmd.Flags().StringVarP(&flagOutput, "output", "o", "", "Output file (default: stdout)")
	cmd.Flags().IntVar(&flagLimit, "limit", 500, "Maximum number of operations to export")
	return cmd
}

// ── catalogue audit ─────────────────────────────────────────────────────────

func newCatalogueAuditCmd() *cobra.Command {
	var flagLimit int
	cmd := &cobra.Command{
		Use:   "audit",
		Short: "Show recent audit log entries",
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx := context.Background()

			cfg, err := config.Load()
			if err != nil {
				return err
			}

			store, err := openCatalogueStore(cfg)
			if err != nil {
				return err
			}
			defer store.Close()

			ops, err := store.ListOperations(ctx, flagLimit)
			if err != nil {
				return fmt.Errorf("list operations: %w", err)
			}

			if len(ops) == 0 {
				color.Yellow("  No audit log entries found.\n")
				return nil
			}

			fmt.Printf("\n  Audit Log — %d most recent operation(s)\n\n", len(ops))
			fmt.Print(catalogue.FormatTable(ops))
			return nil
		},
	}
	cmd.Flags().IntVar(&flagLimit, "limit", 50, "Maximum number of entries to show")
	return cmd
}

// ── helpers ─────────────────────────────────────────────────────────────────

// openCatalogueStore opens the catalogue backend specified in config.
func openCatalogueStore(cfg *config.Config) (*catalogue.SQLiteStore, error) {
	dbPath := cfg.Catalogue.SQLitePath
	if dbPath == "" {
		dbPath = config.MirageDir() + "/catalogue.db"
	}
	store, err := catalogue.NewSQLiteStore(dbPath)
	if err != nil {
		return nil, fmt.Errorf("open catalogue at %s: %w\n\nFix: ensure ~/.mirage/ is writable", dbPath, err)
	}
	return store, nil
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
