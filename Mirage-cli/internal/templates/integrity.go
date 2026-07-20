// Package templates — integrity.go
// SHA256 integrity verification for Terraform template files.
// Before every `terraform apply`, the CLI verifies that the local template
// files match their expected hashes. This prevents supply-chain attacks
// and accidental template modification.
package templates

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// FileHash is a filename → SHA256 hex hash pair.
type FileHash struct {
	File string `json:"file"`
	SHA256 string `json:"sha256"`
}

// ScenarioHashes holds the expected hashes for a single scenario's files.
type ScenarioHashes struct {
	ScenarioNum int        `json:"scenario_num"`
	Files       []FileHash `json:"files"`
}

// HashManifest is a per-source integrity manifest (manifest.json in the repo root).
type HashManifest struct {
	GeneratedAt string                     `json:"generated_at"`
	Scenarios   map[int]*ScenarioHashes    `json:"scenarios"`
}

// VerifyScenario verifies all key template files for a scenario against their expected hashes.
// Returns a list of integrity violations (empty = all good).
func VerifyScenario(scenarioDir string, expected *ScenarioHashes) []string {
	if expected == nil {
		// No manifest available — cannot verify; skip (warn only).
		return nil
	}

	var violations []string
	for _, fh := range expected.Files {
		path := filepath.Join(scenarioDir, fh.File)
		actual, err := SHA256File(path)
		if err != nil {
			violations = append(violations, fmt.Sprintf("%s: cannot read: %v", fh.File, err))
			continue
		}
		if actual != fh.SHA256 {
			violations = append(violations, fmt.Sprintf(
				"%s: hash mismatch\n  expected: %s\n  actual:   %s",
				fh.File, fh.SHA256, actual))
		}
	}
	return violations
}

// SHA256File computes the SHA256 hex digest of a file.
func SHA256File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", fmt.Errorf("hash %s: %w", path, err)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// BuildScenarioHashes generates a ScenarioHashes for a local scenario directory.
// Useful when generating a new manifest (e.g. during release).
func BuildScenarioHashes(number int, scenarioDir string) (*ScenarioHashes, error) {
	filesToHash := []string{"main.tf", "variables.tf", "outputs.tf"}

	sh := &ScenarioHashes{ScenarioNum: number}
	for _, fname := range filesToHash {
		path := filepath.Join(scenarioDir, fname)
		if _, err := os.Stat(path); err != nil {
			continue // optional file
		}
		hash, err := SHA256File(path)
		if err != nil {
			return nil, err
		}
		sh.Files = append(sh.Files, FileHash{File: fname, SHA256: hash})
	}
	return sh, nil
}

// ReadHashManifest reads a JSON hash manifest from disk.
// Returns nil, nil if not found (integrity check is skipped).
func ReadHashManifest(path string) (*HashManifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read hash manifest %s: %w", path, err)
	}

	var m HashManifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parse hash manifest: %w", err)
	}
	return &m, nil
}

// DefaultHashManifestPath returns the canonical path for the hash manifest.
func DefaultHashManifestPath(cacheDir string) string {
	return filepath.Join(cacheDir, "integrity.json")
}
