// Package catalogue — sqlite.go
// SQLite backend implementation of the Store interface.
// Uses modernc.org/sqlite (CGo-free) for portability.
// DB lives at ~/.mirage/catalogue.db with 0600 permissions.
package catalogue

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"

	"github.com/mirage-security/mirage/pkg/models"
)

// SQLiteStore implements Store using a local SQLite database.
type SQLiteStore struct {
	db *sql.DB
}

// NewSQLiteStore opens (or creates) the catalogue database at dbPath.
// The file is created with 0600 permissions.
func NewSQLiteStore(dbPath string) (*SQLiteStore, error) {
	if err := os.MkdirAll(filepath.Dir(dbPath), 0700); err != nil {
		return nil, fmt.Errorf("create catalogue dir: %w", err)
	}

	// Create file with 0600 if it doesn't exist.
	if _, err := os.Stat(dbPath); os.IsNotExist(err) {
		f, err := os.OpenFile(dbPath, os.O_CREATE|os.O_RDWR, 0600)
		if err != nil {
			return nil, fmt.Errorf("create catalogue.db: %w", err)
		}
		f.Close()
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("open catalogue.db: %w", err)
	}

	store := &SQLiteStore{db: db}
	if err := store.migrate(); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate catalogue.db: %w", err)
	}
	return store, nil
}

// migrate creates tables and indices if they don't exist.
func (s *SQLiteStore) migrate() error {
	ddl := []string{
		`CREATE TABLE IF NOT EXISTS resources (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			account_id    TEXT    NOT NULL,
			spoke_alias   TEXT    NOT NULL,
			scenario_num  INTEGER NOT NULL,
			scenario_name TEXT    NOT NULL,
			resource_type TEXT    NOT NULL,
			resource_name TEXT    NOT NULL,
			arn           TEXT    NOT NULL DEFAULT '',
			deployed_at   DATETIME NOT NULL,
			destroyed_at  DATETIME,
			last_verified DATETIME,
			deployed_by   TEXT    NOT NULL DEFAULT '',
			tf_state_path TEXT    NOT NULL DEFAULT '',
			status        TEXT    NOT NULL DEFAULT 'active'
		)`,
		`CREATE INDEX IF NOT EXISTS idx_resources_spoke   ON resources(spoke_alias)`,
		`CREATE INDEX IF NOT EXISTS idx_resources_scenario ON resources(scenario_num)`,
		`CREATE INDEX IF NOT EXISTS idx_resources_status  ON resources(status)`,
		`CREATE TABLE IF NOT EXISTS operations_log (
			id           INTEGER PRIMARY KEY AUTOINCREMENT,
			timestamp    DATETIME NOT NULL,
			operator     TEXT     NOT NULL,
			command      TEXT     NOT NULL,
			account_id   TEXT     NOT NULL,
			spoke_alias  TEXT     NOT NULL DEFAULT '',
			scenario_num INTEGER  NOT NULL DEFAULT 0,
			action       TEXT     NOT NULL,
			result       TEXT     NOT NULL,
			details      TEXT     NOT NULL DEFAULT ''
		)`,
		`CREATE INDEX IF NOT EXISTS idx_ops_timestamp ON operations_log(timestamp)`,
		`CREATE INDEX IF NOT EXISTS idx_ops_spoke     ON operations_log(spoke_alias)`,
	}

	for _, stmt := range ddl {
		if _, err := s.db.Exec(stmt); err != nil {
			return fmt.Errorf("DDL error: %w", err)
		}
	}
	return nil
}

// RegisterResource inserts a new resource entry and returns its ID.
func (s *SQLiteStore) RegisterResource(ctx context.Context, r models.Resource) (int64, error) {
	result, err := s.db.ExecContext(ctx,
		`INSERT INTO resources
			(account_id, spoke_alias, scenario_num, scenario_name, resource_type,
			 resource_name, arn, deployed_at, deployed_by, tf_state_path, status)
		VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
		r.AccountID, r.SpokeAlias, r.ScenarioNum, r.ScenarioName, r.ResourceType,
		r.ResourceName, r.ARN, r.DeployedAt.UTC(), r.DeployedBy, r.TFStatePath, r.Status,
	)
	if err != nil {
		return 0, fmt.Errorf("register resource: %w", err)
	}
	return result.LastInsertId()
}

// DeregisterResource marks a resource as destroyed (retains history).
func (s *SQLiteStore) DeregisterResource(ctx context.Context, id int64, operator string) error {
	now := time.Now().UTC()
	_, err := s.db.ExecContext(ctx,
		`UPDATE resources SET status='destroyed', destroyed_at=? WHERE id=?`,
		now, id)
	if err != nil {
		return fmt.Errorf("deregister resource %d: %w", id, err)
	}
	return nil
}

// GetResource fetches a resource by ID.
func (s *SQLiteStore) GetResource(ctx context.Context, id int64) (*models.Resource, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT id, account_id, spoke_alias, scenario_num, scenario_name,
		        resource_type, resource_name, arn, deployed_at, destroyed_at,
		        last_verified, deployed_by, tf_state_path, status
		FROM resources WHERE id=?`, id)

	return scanResource(row)
}

// ListResources returns resources matching the filter.
func (s *SQLiteStore) ListResources(ctx context.Context, filter ResourceFilter) ([]models.Resource, error) {
	query := `SELECT id, account_id, spoke_alias, scenario_num, scenario_name,
	                 resource_type, resource_name, arn, deployed_at, destroyed_at,
	                 last_verified, deployed_by, tf_state_path, status
	          FROM resources WHERE 1=1`
	var args []interface{}

	if filter.AccountID != "" {
		query += " AND account_id=?"
		args = append(args, filter.AccountID)
	}
	if filter.SpokeAlias != "" {
		query += " AND spoke_alias=?"
		args = append(args, filter.SpokeAlias)
	}
	if filter.ScenarioNum != 0 {
		query += " AND scenario_num=?"
		args = append(args, filter.ScenarioNum)
	}
	if filter.Status != "" {
		query += " AND status=?"
		args = append(args, filter.Status)
	}
	query += " ORDER BY deployed_at DESC"

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list resources: %w", err)
	}
	defer rows.Close()

	var resources []models.Resource
	for rows.Next() {
		r, err := scanResource(rows)
		if err != nil {
			return nil, err
		}
		resources = append(resources, *r)
	}
	return resources, rows.Err()
}

// UpdateResourceStatus updates a resource's status field.
func (s *SQLiteStore) UpdateResourceStatus(ctx context.Context, id int64, status string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE resources SET status=? WHERE id=?`, status, id)
	return err
}

// SetLastVerified updates the last_verified timestamp for a resource.
func (s *SQLiteStore) SetLastVerified(ctx context.Context, id int64, t time.Time) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE resources SET last_verified=? WHERE id=?`, t.UTC(), id)
	return err
}

// LogOperation appends an audit log entry.
func (s *SQLiteStore) LogOperation(ctx context.Context, op models.Operation) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO operations_log
			(timestamp, operator, command, account_id, spoke_alias, scenario_num, action, result, details)
		VALUES (?,?,?,?,?,?,?,?,?)`,
		op.Timestamp.UTC(), op.Operator, op.Command, op.AccountID,
		op.SpokeAlias, op.ScenarioNum, op.Action, op.Result, op.Details,
	)
	if err != nil {
		return fmt.Errorf("log operation: %w", err)
	}
	return nil
}

// ListOperations returns the most recent `limit` operations.
func (s *SQLiteStore) ListOperations(ctx context.Context, limit int) ([]models.Operation, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, timestamp, operator, command, account_id, spoke_alias,
		        scenario_num, action, result, details
		FROM operations_log ORDER BY timestamp DESC LIMIT ?`, limit)
	if err != nil {
		return nil, fmt.Errorf("list operations: %w", err)
	}
	defer rows.Close()

	var ops []models.Operation
	for rows.Next() {
		var op models.Operation
		var ts string
		err := rows.Scan(&op.ID, &ts, &op.Operator, &op.Command, &op.AccountID,
			&op.SpokeAlias, &op.ScenarioNum, &op.Action, &op.Result, &op.Details)
		if err != nil {
			return nil, fmt.Errorf("scan operation: %w", err)
		}
		op.Timestamp, _ = time.Parse(time.RFC3339, ts)
		ops = append(ops, op)
	}
	return ops, rows.Err()
}

// MarkOrphaned marks a resource as orphaned (in catalogue but not in AWS).
func (s *SQLiteStore) MarkOrphaned(ctx context.Context, id int64) error {
	return s.UpdateResourceStatus(ctx, id, "orphaned")
}

// Close closes the database connection.
func (s *SQLiteStore) Close() error {
	return s.db.Close()
}

// ─── helpers ─────────────────────────────────────────────────────────────────

type scanner interface {
	Scan(dest ...interface{}) error
}

func scanResource(row scanner) (*models.Resource, error) {
	var r models.Resource
	var deployedAt string
	var destroyedAt, lastVerified sql.NullString

	err := row.Scan(
		&r.ID, &r.AccountID, &r.SpokeAlias, &r.ScenarioNum, &r.ScenarioName,
		&r.ResourceType, &r.ResourceName, &r.ARN, &deployedAt, &destroyedAt,
		&lastVerified, &r.DeployedBy, &r.TFStatePath, &r.Status,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("resource not found")
		}
		return nil, fmt.Errorf("scan resource: %w", err)
	}

	r.DeployedAt, _ = time.Parse(time.RFC3339, deployedAt)

	if destroyedAt.Valid {
		t, _ := time.Parse(time.RFC3339, destroyedAt.String)
		r.DestroyedAt = &t
	}
	if lastVerified.Valid {
		t, _ := time.Parse(time.RFC3339, lastVerified.String)
		r.LastVerified = &t
	}
	return &r, nil
}
