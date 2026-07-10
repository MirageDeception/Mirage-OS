package discovery

import (
	"strings"

	"github.com/mirage-security/mirage/pkg/models"
)

// Filter applies service and category filters to a list of scenarios.
type Filter struct {
	Service  string
	Category string
}

// Apply returns only the scenarios that match the filter.
// Empty filter fields match all scenarios.
func (f *Filter) Apply(scenarios []*models.ScenarioManifest) []*models.ScenarioManifest {
	if f.Service == "" && f.Category == "" {
		return scenarios
	}

	var result []*models.ScenarioManifest
	for _, s := range scenarios {
		if f.Service != "" && !strings.EqualFold(s.Service, f.Service) {
			continue
		}
		if f.Category != "" && !strings.EqualFold(s.Category, f.Category) {
			continue
		}
		result = append(result, s)
	}
	return result
}

// KnownServices returns the set of distinct services across all scenarios.
func KnownServices(scenarios []*models.ScenarioManifest) []string {
	seen := make(map[string]bool)
	for _, s := range scenarios {
		seen[s.Service] = true
	}
	result := make([]string, 0, len(seen))
	for k := range seen {
		result = append(result, k)
	}
	return result
}

// KnownCategories returns the set of distinct categories.
func KnownCategories(scenarios []*models.ScenarioManifest) []string {
	seen := make(map[string]bool)
	for _, s := range scenarios {
		seen[s.Category] = true
	}
	result := make([]string, 0, len(seen))
	for k := range seen {
		result = append(result, k)
	}
	return result
}
