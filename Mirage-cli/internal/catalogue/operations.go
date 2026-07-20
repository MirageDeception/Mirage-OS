// Package catalogue — operations.go
// High-level operations: Register, Deregister, Sync that compose Store primitives.
// All mutating operations log to the audit trail before returning.
package catalogue

import (
	"context"
	"fmt"
	"time"

	"github.com/mirage-security/mirage/pkg/models"
)

// RegisterOpts are the inputs for registering a deployed resource.
type RegisterOpts struct {
	AccountID    string
	SpokeAlias   string
	ScenarioNum  int
	ScenarioName string
	ResourceType string
	ResourceName string
	ARN          string
	DeployedBy   string // STS principal ARN of the operator
	TFStatePath  string
}

// Register adds a resource to the catalogue and logs the operation.
// Returns the new resource ID.
func Register(ctx context.Context, store Store, opts RegisterOpts) (int64, error) {
	r := models.Resource{
		AccountID:    opts.AccountID,
		SpokeAlias:   opts.SpokeAlias,
		ScenarioNum:  opts.ScenarioNum,
		ScenarioName: opts.ScenarioName,
		ResourceType: opts.ResourceType,
		ResourceName: opts.ResourceName,
		ARN:          opts.ARN,
		DeployedAt:   time.Now().UTC(),
		DeployedBy:   opts.DeployedBy,
		TFStatePath:  opts.TFStatePath,
		Status:       "active",
	}

	// Audit BEFORE the action to ensure it's recorded even if registration fails.
	_ = store.LogOperation(ctx, models.Operation{
		Timestamp:   time.Now().UTC(),
		Operator:    opts.DeployedBy,
		Command:     "mirage scenario deploy",
		AccountID:   opts.AccountID,
		SpokeAlias:  opts.SpokeAlias,
		ScenarioNum: opts.ScenarioNum,
		Action:      "deploy",
		Result:      "pending",
		Details:     fmt.Sprintf(`{"resource_type":%q,"resource_name":%q}`, opts.ResourceType, opts.ResourceName),
	})

	id, err := store.RegisterResource(ctx, r)
	if err != nil {
		return 0, fmt.Errorf("register resource: %w", err)
	}

	// Update audit log with success result.
	_ = store.LogOperation(ctx, models.Operation{
		Timestamp:   time.Now().UTC(),
		Operator:    opts.DeployedBy,
		Command:     "mirage scenario deploy",
		AccountID:   opts.AccountID,
		SpokeAlias:  opts.SpokeAlias,
		ScenarioNum: opts.ScenarioNum,
		Action:      "deploy",
		Result:      "success",
		Details:     fmt.Sprintf(`{"id":%d,"arn":%q}`, id, opts.ARN),
	})

	return id, nil
}

// DeregisterOpts are the inputs for marking a resource destroyed.
type DeregisterOpts struct {
	ResourceID  int64
	Operator    string
	AccountID   string
	SpokeAlias  string
	ScenarioNum int
}

// Deregister marks a resource as destroyed and logs the operation.
func Deregister(ctx context.Context, store Store, opts DeregisterOpts) error {
	_ = store.LogOperation(ctx, models.Operation{
		Timestamp:   time.Now().UTC(),
		Operator:    opts.Operator,
		Command:     "mirage scenario destroy",
		AccountID:   opts.AccountID,
		SpokeAlias:  opts.SpokeAlias,
		ScenarioNum: opts.ScenarioNum,
		Action:      "destroy",
		Result:      "pending",
		Details:     fmt.Sprintf(`{"resource_id":%d}`, opts.ResourceID),
	})

	if err := store.DeregisterResource(ctx, opts.ResourceID, opts.Operator); err != nil {
		return fmt.Errorf("deregister resource %d: %w", opts.ResourceID, err)
	}

	_ = store.LogOperation(ctx, models.Operation{
		Timestamp:   time.Now().UTC(),
		Operator:    opts.Operator,
		Command:     "mirage scenario destroy",
		AccountID:   opts.AccountID,
		SpokeAlias:  opts.SpokeAlias,
		ScenarioNum: opts.ScenarioNum,
		Action:      "destroy",
		Result:      "success",
	})
	return nil
}

// SyncResult summarises the results of a Sync operation.
type SyncResult struct {
	Orphaned int // in catalogue, not verifiable in AWS
	InSync   int // confirmed present and active
}

// MarkVerified updates the last_verified timestamp for all resources of a scenario.
func MarkVerified(ctx context.Context, store Store, accountID, spokeAlias string, scenarioNum int) error {
	resources, err := store.ListResources(ctx, ResourceFilter{
		AccountID:   accountID,
		SpokeAlias:  spokeAlias,
		ScenarioNum: scenarioNum,
		Status:      "active",
	})
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	for _, r := range resources {
		if err := store.SetLastVerified(ctx, r.ID, now); err != nil {
			return fmt.Errorf("set last_verified for resource %d: %w", r.ID, err)
		}
	}
	return nil
}

// OpenStore opens the appropriate catalogue backend based on config.
// backendType: "sqlite" (default) or "dynamodb"
// dbPath: path for SQLite (e.g. ~/.mirage/catalogue.db)
// For DynamoDB, caller must pass a pre-initialised DynamoDBStore.
func OpenSQLite(dbPath string) (*SQLiteStore, error) {
	return NewSQLiteStore(dbPath)
}
