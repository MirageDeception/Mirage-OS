// Package catalogue defines the Store interface and shared types.
// Two backends implement it: sqlite (local) and dynamodb (team/shared).
package catalogue

import (
	"context"
	"time"

	"github.com/mirage-security/mirage/pkg/models"
)

// Store is the interface all catalogue backends must implement.
// All mutating methods write an audit log entry before returning.
type Store interface {
	// Resource CRUD
	RegisterResource(ctx context.Context, r models.Resource) (int64, error)
	DeregisterResource(ctx context.Context, id int64, operator string) error
	GetResource(ctx context.Context, id int64) (*models.Resource, error)
	ListResources(ctx context.Context, filter ResourceFilter) ([]models.Resource, error)
	UpdateResourceStatus(ctx context.Context, id int64, status string) error
	SetLastVerified(ctx context.Context, id int64, t time.Time) error

	// Audit log
	LogOperation(ctx context.Context, op models.Operation) error
	ListOperations(ctx context.Context, limit int) ([]models.Operation, error)

	// Sync
	MarkOrphaned(ctx context.Context, id int64) error

	// Lifecycle
	Close() error
}

// ResourceFilter narrows ListResources results.
type ResourceFilter struct {
	AccountID   string
	SpokeAlias  string
	ScenarioNum int    // 0 = all
	Status      string // "active" | "destroyed" | "orphaned" | "" (all)
}

// SyncState represents one resource's reconciliation status.
type SyncState string

const (
	SyncStateMatch   SyncState = "match"
	SyncStateOrphan  SyncState = "orphan"  // in catalogue, not in AWS
	SyncStatePhantom SyncState = "phantom" // in AWS, not in catalogue
)
