// Package discovery — manifest.go
// Provides helpers for writing and reading aggregated scenario manifests
// (JSON index files) that accelerate catalogue lookups and offline scenario browsing.
package discovery

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/mirage-security/mirage/pkg/models"
)

// ManifestIndex is an aggregated index of all scenarios at a given template source.
// Stored as ~/.mirage/templates/manifest.json for offline use.
type ManifestIndex struct {
	GeneratedAt time.Time                         `json:"generated_at"`
	SourcePath  string                            `json:"source_path"`
	Scenarios   map[int]*models.ScenarioManifest  `json:"scenarios"` // number → manifest
}

// BuildManifestIndex scans a template source and builds an in-memory index.
func BuildManifestIndex(sourcePath string) (*ManifestIndex, error) {
	scanner := NewScanner(sourcePath)
	manifests, err := scanner.ScanAll()
	if err != nil {
		return nil, fmt.Errorf("scan %s: %w", sourcePath, err)
	}

	index := &ManifestIndex{
		GeneratedAt: time.Now().UTC(),
		SourcePath:  sourcePath,
		Scenarios:   make(map[int]*models.ScenarioManifest, len(manifests)),
	}
	for _, m := range manifests {
		index.Scenarios[m.Number] = m
	}
	return index, nil
}

// WriteManifestIndex serialises an index to a JSON file.
func WriteManifestIndex(index *ManifestIndex, destPath string) error {
	if err := os.MkdirAll(filepath.Dir(destPath), 0700); err != nil {
		return fmt.Errorf("create dir for manifest: %w", err)
	}
	data, err := json.MarshalIndent(index, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal manifest: %w", err)
	}
	if err := os.WriteFile(destPath, data, 0600); err != nil {
		return fmt.Errorf("write manifest %s: %w", destPath, err)
	}
	return nil
}

// ReadManifestIndex reads a cached manifest index from disk.
func ReadManifestIndex(path string) (*ManifestIndex, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil // cache miss — caller should build
		}
		return nil, fmt.Errorf("read manifest %s: %w", path, err)
	}

	var index ManifestIndex
	if err := json.Unmarshal(data, &index); err != nil {
		return nil, fmt.Errorf("parse manifest %s: %w", path, err)
	}
	return &index, nil
}

// Get returns the manifest for a specific scenario number.
// Returns nil, nil if not found.
func (m *ManifestIndex) Get(number int) *models.ScenarioManifest {
	return m.Scenarios[number]
}

// All returns all scenario manifests sorted by number.
func (m *ManifestIndex) All() []*models.ScenarioManifest {
	out := make([]*models.ScenarioManifest, 0, len(m.Scenarios))
	for _, s := range m.Scenarios {
		out = append(out, s)
	}
	// Sort by number.
	for i := 0; i < len(out)-1; i++ {
		for j := i + 1; j < len(out); j++ {
			if out[i].Number > out[j].Number {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out
}

// DefaultManifestPath returns the canonical path for the cached manifest index.
// mirageDir is typically ~/.mirage/
func DefaultManifestPath(mirageDir string) string {
	return filepath.Join(mirageDir, "templates", "manifest.json")
}
