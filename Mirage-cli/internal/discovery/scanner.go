// Package discovery scans template sources and parses scenario manifests.
package discovery

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
	"github.com/mirage-security/mirage/pkg/models"
)

// Scanner walks a template source and returns all available scenarios.
type Scanner struct {
	sourcePath string
}

// NewScanner creates a scanner pointing at a local filesystem template source.
func NewScanner(sourcePath string) *Scanner {
	return &Scanner{sourcePath: sourcePath}
}

// ScanAll returns all valid scenarios found in the template source.
// A scenario directory is valid if it contains both main.tf and scenario.yaml.
// Scenarios missing scenario.yaml are skipped with a warning.
func (s *Scanner) ScanAll() ([]*models.ScenarioManifest, error) {
	entries, err := os.ReadDir(s.sourcePath)
	if err != nil {
		return nil, fmt.Errorf("read template source %s: %w", s.sourcePath, err)
	}

	var manifests []*models.ScenarioManifest

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if !strings.HasPrefix(entry.Name(), "scenario-") {
			continue
		}

		scenarioDir := filepath.Join(s.sourcePath, entry.Name())

		// Must have main.tf to be a real scenario.
		if _, err := os.Stat(filepath.Join(scenarioDir, "main.tf")); err != nil {
			continue
		}

		manifestPath := filepath.Join(scenarioDir, "scenario.yaml")
		manifest, err := parseManifest(manifestPath)
		if err != nil {
			// Skip scenarios without manifests (warn but continue).
			fmt.Fprintf(os.Stderr, "warning: scenario %s missing scenario.yaml, skipping\n", entry.Name())
			continue
		}

		manifests = append(manifests, manifest)
	}

	// Sort by scenario number.
	sort.Slice(manifests, func(i, j int) bool {
		return manifests[i].Number < manifests[j].Number
	})

	return manifests, nil
}

// GetScenario returns the manifest for a specific scenario number.
func (s *Scanner) GetScenario(number int) (*models.ScenarioManifest, error) {
	dirName := fmt.Sprintf("scenario-%d", number)
	scenarioDir := filepath.Join(s.sourcePath, dirName)

	manifestPath := filepath.Join(scenarioDir, "scenario.yaml")
	manifest, err := parseManifest(manifestPath)
	if err != nil {
		return nil, fmt.Errorf("scenario %d: %w", number, err)
	}
	return manifest, nil
}

// ScenarioDir returns the filesystem path to a scenario's template directory.
func (s *Scanner) ScenarioDir(number int) string {
	return filepath.Join(s.sourcePath, fmt.Sprintf("scenario-%d", number))
}

// parseManifest reads and parses a scenario.yaml file.
func parseManifest(path string) (*models.ScenarioManifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("scenario.yaml not found at %s", path)
		}
		return nil, fmt.Errorf("read %s: %w", path, err)
	}

	var manifest models.ScenarioManifest
	if err := yaml.Unmarshal(data, &manifest); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}

	if manifest.Number == 0 || manifest.Name == "" {
		return nil, fmt.Errorf("invalid manifest %s: missing number or name", path)
	}

	return &manifest, nil
}

// ScenarioNumberFromDir extracts the number from a directory name like "scenario-7".
func ScenarioNumberFromDir(dirName string) (int, bool) {
	parts := strings.SplitN(dirName, "-", 2)
	if len(parts) != 2 {
		return 0, false
	}
	n, err := strconv.Atoi(parts[1])
	if err != nil {
		return 0, false
	}
	return n, true
}
