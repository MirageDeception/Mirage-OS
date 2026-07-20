// Package catalogue — audit.go
// Audit helpers: format operations for display, export, and detect sensitive fields.
// The audit log is append-only; no update/delete operations are ever performed.
package catalogue

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/mirage-security/mirage/pkg/models"
)

// AuditLog wraps a Store with audit-focused query and export helpers.
type AuditLog struct {
	store Store
}

// NewAuditLog creates an AuditLog helper.
func NewAuditLog(store Store) *AuditLog {
	return &AuditLog{store: store}
}

// Recent returns the N most recent operations.
func (a *AuditLog) Recent(ctx context.Context, n int) ([]models.Operation, error) {
	return a.store.ListOperations(ctx, n)
}

// LogAbuse records a scenario abuse execution. This is the highest-severity
// audit entry type — always logged with full context.
func (a *AuditLog) LogAbuse(ctx context.Context, operator, accountID, spokeAlias string, scenarioNum int, result string) error {
	return a.store.LogOperation(ctx, models.Operation{
		Timestamp:   time.Now().UTC(),
		Operator:    operator,
		Command:     "mirage scenario abuse",
		AccountID:   accountID,
		SpokeAlias:  spokeAlias,
		ScenarioNum: scenarioNum,
		Action:      "abuse",
		Result:      result,
		Details:     fmt.Sprintf(`{"severity":"CRITICAL","operator":%q}`, operator),
	})
}

// LogVerify records a synthetic drill verification.
func (a *AuditLog) LogVerify(ctx context.Context, operator, accountID, spokeAlias string, scenarioNum int, result, latency string) error {
	return a.store.LogOperation(ctx, models.Operation{
		Timestamp:   time.Now().UTC(),
		Operator:    operator,
		Command:     "mirage verify",
		AccountID:   accountID,
		SpokeAlias:  spokeAlias,
		ScenarioNum: scenarioNum,
		Action:      "verify",
		Result:      result,
		Details:     fmt.Sprintf(`{"latency_ms":%q}`, latency),
	})
}

// ExportJSON serialises operations as JSON.
func (a *AuditLog) ExportJSON(ctx context.Context, limit int, w io.Writer) error {
	ops, err := a.store.ListOperations(ctx, limit)
	if err != nil {
		return err
	}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(ops)
}

// ExportCSV serialises operations as CSV.
func (a *AuditLog) ExportCSV(ctx context.Context, limit int, w io.Writer) error {
	ops, err := a.store.ListOperations(ctx, limit)
	if err != nil {
		return err
	}

	cw := csv.NewWriter(w)
	_ = cw.Write([]string{"timestamp", "operator", "command", "account_id", "spoke_alias", "scenario_num", "action", "result", "details"})
	for _, op := range ops {
		_ = cw.Write([]string{
			op.Timestamp.Format(time.RFC3339),
			op.Operator,
			op.Command,
			op.AccountID,
			op.SpokeAlias,
			fmt.Sprintf("%d", op.ScenarioNum),
			op.Action,
			op.Result,
			op.Details,
		})
	}
	cw.Flush()
	return cw.Error()
}

// FormatTable returns a human-readable table of operations for terminal display.
func FormatTable(ops []models.Operation) string {
	if len(ops) == 0 {
		return "  (no operations logged)\n"
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("  %-22s %-20s %-10s %-12s %-8s %s\n",
		"TIMESTAMP", "OPERATOR", "SPOKE", "ACTION", "RESULT", "SCENARIO"))
	sb.WriteString("  " + strings.Repeat("─", 90) + "\n")

	for _, op := range ops {
		operator := op.Operator
		if len(operator) > 20 {
			operator = "..." + operator[len(operator)-17:]
		}
		ts := op.Timestamp.Format("2006-01-02 15:04:05")
		sb.WriteString(fmt.Sprintf("  %-22s %-20s %-10s %-12s %-8s %d\n",
			ts, operator, op.SpokeAlias, op.Action, op.Result, op.ScenarioNum))
	}
	return sb.String()
}

// SanitizeDetails removes sensitive fields from the details JSON blob
// before writing to logs. Strips: access_key, secret, token, password.
func SanitizeDetails(details string) string {
	sensitive := []string{"access_key", "secret", "token", "password", "credential"}
	for _, k := range sensitive {
		if strings.Contains(strings.ToLower(details), k) {
			return `{"sanitized":"true","reason":"contains_sensitive_fields"}`
		}
	}
	return details
}
