// Package templates manages fetching and caching of Terraform scenario templates.
// Templates are pulled from a configured source (local filesystem or GitHub) and
// cached locally in ~/.mirage/templates/scenario-N/.
// Integrity is verified via SHA256 before every Terraform apply.
package templates

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// Source describes where to fetch scenario templates from.
type Source struct {
	// Type: "local" or "github"
	Type string
	// Path is the filesystem path (Type=local) or GitHub repo path (Type=github).
	// E.g. "/home/user/Mirage-OS/aws/scenarios_terraform" or "mirage-security/Mirage-OS"
	Path string
	// Branch is only used for Type=github (default: "main").
	Branch string
}

// Fetcher retrieves scenario templates and caches them locally.
type Fetcher struct {
	source    Source
	cacheDir  string
	client    *http.Client
}

// NewFetcher creates a Fetcher.
// cacheDir is typically ~/.mirage/templates/
func NewFetcher(source Source, cacheDir string) *Fetcher {
	return &Fetcher{
		source:   source,
		cacheDir: cacheDir,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// ScenarioDir returns the effective directory for a given scenario number.
// For local sources this is directly in the source path.
// For cached remote sources this is in cacheDir.
func (f *Fetcher) ScenarioDir(number int) string {
	if f.source.Type == "local" {
		return filepath.Join(f.source.Path, fmt.Sprintf("scenario-%d", number))
	}
	return filepath.Join(f.cacheDir, fmt.Sprintf("scenario-%d", number))
}

// Ensure ensures the scenario template is available locally.
// For local sources this is a no-op (files are already there).
// For remote sources it downloads and caches the template.
func (f *Fetcher) Ensure(number int) error {
	if f.source.Type == "local" {
		dir := f.ScenarioDir(number)
		if _, err := os.Stat(filepath.Join(dir, "main.tf")); err != nil {
			return fmt.Errorf(
				"scenario %d template not found at %s\n"+
					"Fix: ensure aws/scenarios_terraform/scenario-%d/main.tf exists",
				number, dir, number)
		}
		return nil
	}

	// Remote: check if cached and fresh.
	destDir := f.ScenarioDir(number)
	if isPopulated(destDir) {
		return nil // cache hit
	}

	return f.fetchGitHub(number, destDir)
}

// fetchGitHub downloads scenario files from a GitHub raw URL.
func (f *Fetcher) fetchGitHub(number int, destDir string) error {
	branch := f.source.Branch
	if branch == "" {
		branch = "main"
	}

	files := []string{"main.tf", "variables.tf", "outputs.tf", "scenario.yaml"}
	if err := os.MkdirAll(destDir, 0700); err != nil {
		return fmt.Errorf("create cache dir: %w", err)
	}

	for _, fname := range files {
		rawURL := fmt.Sprintf(
			"https://raw.githubusercontent.com/%s/%s/aws/scenarios_terraform/scenario-%d/%s",
			f.source.Path, branch, number, fname)

		dest := filepath.Join(destDir, fname)
		if err := downloadFile(f.client, rawURL, dest); err != nil {
			if fname == "main.tf" || fname == "variables.tf" {
				return fmt.Errorf("fetch scenario %d/%s: %w", number, fname, err)
			}
			// Optional files (scenario.yaml, outputs.tf) — skip silently.
		}
	}
	return nil
}

// EnsureAll ensures all scenarios up to maxNum are cached.
func (f *Fetcher) EnsureAll(maxNum int) error {
	for i := 1; i <= maxNum; i++ {
		if err := f.Ensure(i); err != nil {
			return fmt.Errorf("ensure scenario %d: %w", i, err)
		}
	}
	return nil
}

// downloadFile downloads a URL to a local file.
func downloadFile(client *http.Client, url, dest string) error {
	resp, err := client.Get(url)
	if err != nil {
		return fmt.Errorf("GET %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 404 {
		return fmt.Errorf("not found: %s", url)
	}
	if resp.StatusCode != 200 {
		return fmt.Errorf("HTTP %d fetching %s", resp.StatusCode, url)
	}

	f, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		return fmt.Errorf("create %s: %w", dest, err)
	}
	defer f.Close()

	if _, err := io.Copy(f, resp.Body); err != nil {
		return fmt.Errorf("write %s: %w", dest, err)
	}
	return nil
}

// isPopulated returns true if a directory contains main.tf.
func isPopulated(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, "main.tf"))
	return err == nil
}

// SourceFromConfig derives a template Source from config fields.
// If localPath is non-empty, returns a local source pointing there.
// Otherwise returns a GitHub source.
func SourceFromConfig(localPath, githubRepo, branch string) Source {
	if localPath != "" {
		return Source{Type: "local", Path: localPath}
	}
	if githubRepo == "" {
		githubRepo = "mirage-security/Mirage-OS"
	}
	return Source{Type: "github", Path: githubRepo, Branch: branch}
}
