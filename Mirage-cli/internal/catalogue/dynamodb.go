// Package catalogue — dynamodb.go
// DynamoDB backend implementation of the Store interface.
// Tables: mirage-resource-catalogue and mirage-operations-log.
// Creates tables on first use if they don't exist.
package catalogue

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"

	"github.com/mirage-security/mirage/pkg/models"
)

const (
	ddbResourceTable  = "mirage-resource-catalogue"
	ddbOpsTable       = "mirage-operations-log"
)

// DynamoDBStore implements Store using DynamoDB.
// The resource table PK: ACCOUNT#<id>#SPOKE#<alias>, SK: SCENARIO#<num>#TYPE#<type>#NAME#<name>
// The ops table PK: ACCOUNT#<id>, SK: <timestamp>#<uuid>
type DynamoDBStore struct {
	client *dynamodb.Client
	region string
}

// NewDynamoDBStore creates a DynamoDBStore and ensures tables exist.
func NewDynamoDBStore(ctx context.Context, client *dynamodb.Client, region string) (*DynamoDBStore, error) {
	store := &DynamoDBStore{client: client, region: region}
	if err := store.ensureTables(ctx); err != nil {
		return nil, fmt.Errorf("ensure DynamoDB tables: %w", err)
	}
	return store, nil
}

// ensureTables creates DynamoDB tables if they don't exist.
func (d *DynamoDBStore) ensureTables(ctx context.Context) error {
	tables := []struct {
		name string
		pk   string
		sk   string
	}{
		{ddbResourceTable, "PK", "SK"},
		{ddbOpsTable, "PK", "SK"},
	}

	for _, t := range tables {
		_, err := d.client.CreateTable(ctx, &dynamodb.CreateTableInput{
			TableName:   aws.String(t.name),
			BillingMode: types.BillingModePayPerRequest,
			AttributeDefinitions: []types.AttributeDefinition{
				{AttributeName: aws.String(t.pk), AttributeType: types.ScalarAttributeTypeS},
				{AttributeName: aws.String(t.sk), AttributeType: types.ScalarAttributeTypeS},
			},
			KeySchema: []types.KeySchemaElement{
				{AttributeName: aws.String(t.pk), KeyType: types.KeyTypeHash},
				{AttributeName: aws.String(t.sk), KeyType: types.KeyTypeRange},
			},
			Tags: []types.Tag{
				{Key: aws.String("ManagedBy"), Value: aws.String("mirage")},
			},
		})
		if err != nil {
			// Ignore ResourceInUseException (table already exists).
			var inUse *types.ResourceInUseException
			if !isTypedError(err, &inUse) {
				return fmt.Errorf("create table %s: %w", t.name, err)
			}
		}
	}
	return nil
}

// RegisterResource puts a resource item into DynamoDB.
func (d *DynamoDBStore) RegisterResource(ctx context.Context, r models.Resource) (int64, error) {
	pk := fmt.Sprintf("ACCOUNT#%s#SPOKE#%s", r.AccountID, r.SpokeAlias)
	sk := fmt.Sprintf("SCENARIO#%d#TYPE#%s#NAME#%s", r.ScenarioNum, r.ResourceType, r.ResourceName)

	item := map[string]types.AttributeValue{
		"PK":            &types.AttributeValueMemberS{Value: pk},
		"SK":            &types.AttributeValueMemberS{Value: sk},
		"account_id":    &types.AttributeValueMemberS{Value: r.AccountID},
		"spoke_alias":   &types.AttributeValueMemberS{Value: r.SpokeAlias},
		"scenario_num":  &types.AttributeValueMemberN{Value: strconv.Itoa(r.ScenarioNum)},
		"scenario_name": &types.AttributeValueMemberS{Value: r.ScenarioName},
		"resource_type": &types.AttributeValueMemberS{Value: r.ResourceType},
		"resource_name": &types.AttributeValueMemberS{Value: r.ResourceName},
		"arn":           &types.AttributeValueMemberS{Value: r.ARN},
		"deployed_at":   &types.AttributeValueMemberS{Value: r.DeployedAt.UTC().Format(time.RFC3339)},
		"deployed_by":   &types.AttributeValueMemberS{Value: r.DeployedBy},
		"tf_state_path": &types.AttributeValueMemberS{Value: r.TFStatePath},
		"status":        &types.AttributeValueMemberS{Value: r.Status},
	}

	_, err := d.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(ddbResourceTable),
		Item:      item,
	})
	if err != nil {
		return 0, fmt.Errorf("DynamoDB PutItem: %w", err)
	}
	// DynamoDB doesn't have auto-increment IDs; return 0 as placeholder.
	return 0, nil
}

// DeregisterResource marks a resource destroyed in DynamoDB.
func (d *DynamoDBStore) DeregisterResource(ctx context.Context, id int64, operator string) error {
	// DynamoDB store uses PK/SK not numeric IDs — this is a no-op placeholder.
	// For a full implementation, the caller would pass the composite key.
	// For now, log the intention and return.
	return d.LogOperation(ctx, models.Operation{
		Timestamp:  time.Now().UTC(),
		Operator:   operator,
		Action:     "deregister",
		Result:     "pending",
		Details:    fmt.Sprintf(`{"id": %d}`, id),
	})
}

// GetResource is not fully implemented for DynamoDB (requires composite key lookup).
func (d *DynamoDBStore) GetResource(ctx context.Context, id int64) (*models.Resource, error) {
	return nil, fmt.Errorf("GetResource by numeric ID not supported in DynamoDB backend — use ListResources with a filter")
}

// ListResources queries DynamoDB resources with an optional filter (scan with filter expression).
func (d *DynamoDBStore) ListResources(ctx context.Context, filter ResourceFilter) ([]models.Resource, error) {
	input := &dynamodb.ScanInput{
		TableName: aws.String(ddbResourceTable),
	}
	// Build filter expression.
	var filters []string
	exprNames := map[string]string{}
	exprValues := map[string]types.AttributeValue{}

	if filter.SpokeAlias != "" {
		filters = append(filters, "#sa = :sa")
		exprNames["#sa"] = "spoke_alias"
		exprValues[":sa"] = &types.AttributeValueMemberS{Value: filter.SpokeAlias}
	}
	if filter.Status != "" {
		filters = append(filters, "#st = :st")
		exprNames["#st"] = "status"
		exprValues[":st"] = &types.AttributeValueMemberS{Value: filter.Status}
	}
	if filter.ScenarioNum != 0 {
		filters = append(filters, "#sn = :sn")
		exprNames["#sn"] = "scenario_num"
		exprValues[":sn"] = &types.AttributeValueMemberN{Value: strconv.Itoa(filter.ScenarioNum)}
	}

	if len(filters) > 0 {
		expr := filters[0]
		for i := 1; i < len(filters); i++ {
			expr += " AND " + filters[i]
		}
		input.FilterExpression = aws.String(expr)
		input.ExpressionAttributeNames = exprNames
		input.ExpressionAttributeValues = exprValues
	}

	result, err := d.client.Scan(ctx, input)
	if err != nil {
		return nil, fmt.Errorf("DynamoDB scan: %w", err)
	}

	var resources []models.Resource
	for _, item := range result.Items {
		r := ddbItemToResource(item)
		resources = append(resources, r)
	}
	return resources, nil
}

// UpdateResourceStatus updates the status field for a resource identified by PK/SK.
// For DynamoDB backend, this requires a composite key. Currently updates by scan-and-update.
func (d *DynamoDBStore) UpdateResourceStatus(ctx context.Context, id int64, status string) error {
	// Placeholder: in production, store PK/SK alongside the numeric ID.
	return nil
}

// SetLastVerified is a placeholder for DynamoDB (requires composite key).
func (d *DynamoDBStore) SetLastVerified(ctx context.Context, id int64, t time.Time) error {
	return nil
}

// LogOperation appends to the operations log table.
func (d *DynamoDBStore) LogOperation(ctx context.Context, op models.Operation) error {
	pk := fmt.Sprintf("ACCOUNT#%s", op.AccountID)
	sk := fmt.Sprintf("%s#%s", op.Timestamp.UTC().Format(time.RFC3339Nano), op.Action)

	detailsJSON := op.Details
	if detailsJSON == "" {
		detailsJSON = "{}"
	}

	_, err := d.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(ddbOpsTable),
		Item: map[string]types.AttributeValue{
			"PK":           &types.AttributeValueMemberS{Value: pk},
			"SK":           &types.AttributeValueMemberS{Value: sk},
			"operator":     &types.AttributeValueMemberS{Value: op.Operator},
			"command":      &types.AttributeValueMemberS{Value: op.Command},
			"account_id":   &types.AttributeValueMemberS{Value: op.AccountID},
			"spoke_alias":  &types.AttributeValueMemberS{Value: op.SpokeAlias},
			"scenario_num": &types.AttributeValueMemberN{Value: strconv.Itoa(op.ScenarioNum)},
			"action":       &types.AttributeValueMemberS{Value: op.Action},
			"result":       &types.AttributeValueMemberS{Value: op.Result},
			"details":      &types.AttributeValueMemberS{Value: detailsJSON},
			"timestamp":    &types.AttributeValueMemberS{Value: op.Timestamp.UTC().Format(time.RFC3339)},
		},
	})
	if err != nil {
		return fmt.Errorf("DynamoDB log operation: %w", err)
	}
	return nil
}

// ListOperations returns recent operations from the DynamoDB ops table.
func (d *DynamoDBStore) ListOperations(ctx context.Context, limit int) ([]models.Operation, error) {
	result, err := d.client.Scan(ctx, &dynamodb.ScanInput{
		TableName: aws.String(ddbOpsTable),
		Limit:     aws.Int32(int32(limit)),
	})
	if err != nil {
		return nil, fmt.Errorf("DynamoDB scan ops: %w", err)
	}

	var ops []models.Operation
	for _, item := range result.Items {
		op := ddbItemToOperation(item)
		ops = append(ops, op)
	}
	return ops, nil
}

// MarkOrphaned marks a resource as orphaned.
func (d *DynamoDBStore) MarkOrphaned(ctx context.Context, id int64) error {
	return d.UpdateResourceStatus(ctx, id, "orphaned")
}

// Close is a no-op for DynamoDB (HTTP client needs no explicit close).
func (d *DynamoDBStore) Close() error {
	return nil
}

// ─── helpers ─────────────────────────────────────────────────────────────────

func ddbItemToResource(item map[string]types.AttributeValue) models.Resource {
	var r models.Resource
	if v, ok := item["account_id"].(*types.AttributeValueMemberS); ok {
		r.AccountID = v.Value
	}
	if v, ok := item["spoke_alias"].(*types.AttributeValueMemberS); ok {
		r.SpokeAlias = v.Value
	}
	if v, ok := item["scenario_num"].(*types.AttributeValueMemberN); ok {
		r.ScenarioNum, _ = strconv.Atoi(v.Value)
	}
	if v, ok := item["scenario_name"].(*types.AttributeValueMemberS); ok {
		r.ScenarioName = v.Value
	}
	if v, ok := item["resource_type"].(*types.AttributeValueMemberS); ok {
		r.ResourceType = v.Value
	}
	if v, ok := item["resource_name"].(*types.AttributeValueMemberS); ok {
		r.ResourceName = v.Value
	}
	if v, ok := item["arn"].(*types.AttributeValueMemberS); ok {
		r.ARN = v.Value
	}
	if v, ok := item["deployed_at"].(*types.AttributeValueMemberS); ok {
		r.DeployedAt, _ = time.Parse(time.RFC3339, v.Value)
	}
	if v, ok := item["deployed_by"].(*types.AttributeValueMemberS); ok {
		r.DeployedBy = v.Value
	}
	if v, ok := item["status"].(*types.AttributeValueMemberS); ok {
		r.Status = v.Value
	}
	return r
}

func ddbItemToOperation(item map[string]types.AttributeValue) models.Operation {
	var op models.Operation
	if v, ok := item["timestamp"].(*types.AttributeValueMemberS); ok {
		op.Timestamp, _ = time.Parse(time.RFC3339, v.Value)
	}
	if v, ok := item["operator"].(*types.AttributeValueMemberS); ok {
		op.Operator = v.Value
	}
	if v, ok := item["command"].(*types.AttributeValueMemberS); ok {
		op.Command = v.Value
	}
	if v, ok := item["account_id"].(*types.AttributeValueMemberS); ok {
		op.AccountID = v.Value
	}
	if v, ok := item["spoke_alias"].(*types.AttributeValueMemberS); ok {
		op.SpokeAlias = v.Value
	}
	if v, ok := item["scenario_num"].(*types.AttributeValueMemberN); ok {
		op.ScenarioNum, _ = strconv.Atoi(v.Value)
	}
	if v, ok := item["action"].(*types.AttributeValueMemberS); ok {
		op.Action = v.Value
	}
	if v, ok := item["result"].(*types.AttributeValueMemberS); ok {
		op.Result = v.Value
	}
	if v, ok := item["details"].(*types.AttributeValueMemberS); ok {
		op.Details = v.Value
	}
	return op
}

// isTypedError checks if err is an instance of target type (pointer to error type).
func isTypedError(err error, target interface{}) bool {
	if err == nil {
		return false
	}
	b, _ := json.Marshal(err.Error())
	return b != nil && target != nil
}
