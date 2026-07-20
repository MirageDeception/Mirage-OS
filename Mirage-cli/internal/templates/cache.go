// Package templates — cache.go
// Local template cache management: refresh, invalidate, and inspect the cache.
package templates

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// CacheInfo describes the state of a cached scenario.
type CacheInfo struct {
	Number    int
	Dir       string
	Populated bool
	ModTime   time.Time
	Files     []string
}

// CacheManager manages the local template cache.
type CacheManager struct {
	cacheDir string
}

// NewCacheManager creates a CacheManager.
// cacheDir is typically ~/.mirage/templates/
func NewCacheManager(cacheDir string) *CacheManager {
	return &CacheManager{cacheDir: cacheDir}
}

// Info returns cache information for a specific scenario.
func (c *CacheManager) Info(number int) (*CacheInfo, error) {
	dir := filepath.Join(c.cacheDir, fmt.Sprintf("scenario-%d", number))
	info := &CacheInfo{
		Number: number,
		Dir:    dir,
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return info, nil // not cached
		}
		return nil, fmt.Errorf("read cache dir %s: %w", dir, err)
	}

	info.Populated = true
	for _, e := range entries {
		info.Files = append(info.Files, e.Name())
		if fi, err := e.Info(); err == nil && fi.ModTime().After(info.ModTime) {
			info.ModTime = fi.ModTime()
		}
	}
	return info, nil
}

// Clear removes a scenario's cached templates.
func (c *CacheManager) Clear(number int) error {
	dir := filepath.Join(c.cacheDir, fmt.Sprintf("scenario-%d", number))
	if err := os.RemoveAll(dir); err != nil {
		return fmt.Errorf("clear cache for scenario %d: %w", number, err)
	}
	return nil
}

// ClearAll removes all cached templates.
func (c *CacheManager) ClearAll() error {
	entries, err := os.ReadDir(c.cacheDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("read cache dir: %w", err)
	}

	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		if err := os.RemoveAll(filepath.Join(c.cacheDir, e.Name())); err != nil {
			return fmt.Errorf("remove %s: %w", e.Name(), err)
		}
	}
	return nil
}

// IsStale returns true if the cache for a scenario is older than maxAge.
// Returns true if not cached at all.
func (c *CacheManager) IsStale(number int, maxAge time.Duration) (bool, error) {
	info, err := c.Info(number)
	if err != nil {
		return true, err
	}
	if !info.Populated {
		return true, nil
	}
	return time.Since(info.ModTime) > maxAge, nil
}

// EnsureDir creates the cache directory if it doesn't exist.
func (c *CacheManager) EnsureDir() error {
	if err := os.MkdirAll(c.cacheDir, 0700); err != nil {
		return fmt.Errorf("create cache dir %s: %w", c.cacheDir, err)
	}
	return nil
}
