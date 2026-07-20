package naming_test

import (
	"testing"

	"github.com/mirage-security/mirage/internal/config"
	"github.com/mirage-security/mirage/internal/naming"
)

// ── resolver tests ─────────────────────────────────────────────────────────────

func testConfig() *config.Config {
	return &config.Config{
		Naming: config.Naming{
			Prefix: "corp",
			Patterns: config.NamingPatterns{
				S3Bucket:       "{prefix}-{scenario_slug}-bucket-{suffix}",
				IAMRole:        "{prefix}-{scenario_slug}-{key}",
				LambdaFunction: "{prefix}-{scenario_slug}-fn-{suffix}",
				SSMParameter:   "/{prefix}/{scenario_slug}/config",
				DynamoDBTable:  "{prefix}-{scenario_slug}-table",
			},
		},
	}
}

func TestResolve_PatternInterpolation(t *testing.T) {
	r := naming.NewResolver(testConfig(), "123456789012", "us-east-1", "dev")
	name, err := r.Resolve("scenario-1", "s3_bucket", "terraform-state", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if name == "" {
		t.Fatal("expected non-empty resolved name")
	}
	if name == "__PLACEHOLDER__" {
		t.Fatal("expected real name, got placeholder")
	}
	t.Logf("resolved s3_bucket: %s", name)
}

func TestResolve_FlagPrefixOverridesConfig(t *testing.T) {
	r := naming.NewResolver(testConfig(), "123456789012", "us-east-1", "dev").
		WithFlagPrefix("test")
	name, err := r.Resolve("scenario-1", "s3_bucket", "terraform-state", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// Name must start with "test-" not "corp-".
	if len(name) < 5 || name[:5] != "test-" {
		t.Errorf("flag prefix not applied: got %q, want prefix 'test-'", name)
	}
}

func TestResolve_ConfigOverrideTakesPrecedence(t *testing.T) {
	cfg := testConfig()
	cfg.Naming.Overrides = map[string]map[string]string{
		"scenario-1": {"s3_bucket": "my-exact-bucket-name"},
	}
	r := naming.NewResolver(cfg, "123456789012", "us-east-1", "dev")
	name, err := r.Resolve("scenario-1", "s3_bucket", "terraform-state", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if name != "my-exact-bucket-name" {
		t.Errorf("override not respected: got %q, want 'my-exact-bucket-name'", name)
	}
}

func TestResolve_UnknownResourceTypeFallsToPlaceholder(t *testing.T) {
	r := naming.NewResolver(testConfig(), "123456789012", "us-east-1", "dev")
	name, err := r.Resolve("scenario-1", "totally_unknown_type", "slug", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if name != "__PLACEHOLDER__" {
		t.Errorf("expected placeholder for unknown type, got %q", name)
	}
}

func TestResolve_MissingVariableReturnsError(t *testing.T) {
	cfg := testConfig()
	// Pattern references {nonexistent} — resolver must error.
	cfg.Naming.Patterns.S3Bucket = "{prefix}-{nonexistent}-{suffix}"
	r := naming.NewResolver(cfg, "123456789012", "us-east-1", "dev")
	_, err := r.Resolve("scenario-1", "s3_bucket", "slug", nil)
	if err == nil {
		t.Fatal("expected error for unresolved variable, got nil")
	}
}

func TestResolveAll_ReturnsMapForAllTypes(t *testing.T) {
	r := naming.NewResolver(testConfig(), "123456789012", "us-east-1", "dev")
	types := []string{"s3_bucket", "iam_role", "dynamodb_table"}
	result, err := r.ResolveAll("scenario-3", "fake-data", types, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, rt := range types {
		if _, ok := result[rt]; !ok {
			t.Errorf("missing resolved name for resource type %q", rt)
		}
	}
}

func TestDeterministicSuffix_Stable(t *testing.T) {
	r := naming.NewResolver(testConfig(), "111122223333", "us-east-1", "prod")
	name1, _ := r.Resolve("scenario-5", "s3_bucket", "slug", nil)
	name2, _ := r.Resolve("scenario-5", "s3_bucket", "slug", nil)
	if name1 != name2 {
		t.Errorf("suffix is not deterministic: %q vs %q", name1, name2)
	}
}

// ── collision detection tests ──────────────────────────────────────────────────

func TestCheckCollisions_DetectsConflict(t *testing.T) {
	cfg := testConfig()
	// Force same override for two scenarios to create collision.
	cfg.Naming.Overrides = map[string]map[string]string{
		"scenario-1": {"s3_bucket": "shared-bucket"},
		"scenario-2": {"s3_bucket": "shared-bucket"},
	}
	r := naming.NewResolver(cfg, "123456789012", "us-east-1", "dev")
	collisions := r.CheckCollisions([]naming.ScenarioNameInput{
		{ScenarioKey: "scenario-1", Slug: "slug1", ResourceTypes: []string{"s3_bucket"}},
		{ScenarioKey: "scenario-2", Slug: "slug2", ResourceTypes: []string{"s3_bucket"}},
	})
	if len(collisions) == 0 {
		t.Fatal("expected collision detection, got none")
	}
}

func TestCheckCollisions_NoneForDistinctSuffixes(t *testing.T) {
	r := naming.NewResolver(testConfig(), "123456789012", "us-east-1", "dev")
	collisions := r.CheckCollisions([]naming.ScenarioNameInput{
		{ScenarioKey: "scenario-1", Slug: "slug1", ResourceTypes: []string{"s3_bucket"}},
		{ScenarioKey: "scenario-2", Slug: "slug2", ResourceTypes: []string{"s3_bucket"}},
	})
	// Different scenario keys produce different deterministic suffixes → no collision.
	if len(collisions) > 0 {
		t.Errorf("unexpected collisions: %v", collisions)
	}
}

// ── tfvars generation tests ────────────────────────────────────────────────────

func TestGenerateTFVars_IncludesRequiredVars(t *testing.T) {
	content, err := naming.GenerateTFVars(
		[]string{"account_id", "bucket_name"},
		map[string]string{"bucket_name": "corp-state-bucket"},
		"123456789012", "us-east-1",
		nil,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, want := range []string{"account_id", "bucket_name", "123456789012", "corp-state-bucket"} {
		if !containsStr(content, want) {
			t.Errorf("tfvars missing %q:\n%s", want, content)
		}
	}
}

func TestGenerateTFVars_ErrorOnMissingVar(t *testing.T) {
	_, err := naming.GenerateTFVars(
		[]string{"account_id", "missing_var"},
		map[string]string{},
		"123456789012", "us-east-1",
		nil,
	)
	if err == nil {
		t.Fatal("expected error for missing required TF variable")
	}
}

func TestScenarioKey_Format(t *testing.T) {
	for n, want := range map[int]string{
		1:  "scenario-1",
		10: "scenario-10",
		19: "scenario-19",
	} {
		if got := naming.ScenarioKey(n); got != want {
			t.Errorf("ScenarioKey(%d) = %q, want %q", n, got, want)
		}
	}
}

// ── variables.go tests ────────────────────────────────────────────────────────

func TestFilterVarsToDeclarations_FiltersCorrectly(t *testing.T) {
	vars := map[string]string{"account_id": "123", "region": "us-east-1", "extra": "ignored"}
	declared := []string{"account_id", "region"}
	filtered := naming.FilterVarsToDeclarations(vars, declared)

	if len(filtered) != 2 {
		t.Errorf("expected 2 vars, got %d: %v", len(filtered), filtered)
	}
	if _, ok := filtered["extra"]; ok {
		t.Error("extra key should have been filtered out")
	}
}

func TestFilterVarsToDeclarations_EmptyDeclaredPassesAll(t *testing.T) {
	vars := map[string]string{"a": "1", "b": "2"}
	filtered := naming.FilterVarsToDeclarations(vars, nil)
	if len(filtered) != 2 {
		t.Errorf("empty declared should return all vars, got %d", len(filtered))
	}
}

// ── helpers ───────────────────────────────────────────────────────────────────

func containsStr(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub ||
		func() bool {
			for i := 0; i <= len(s)-len(sub); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
			return false
		}())
}
