// Package config manages reading and writing ~/.mirage/config.yaml.
package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

const (
	CurrentVersion = "1"
	ConfigDir      = ".mirage"
	ConfigFile     = "config.yaml"
)

// ConfigPath returns the absolute path to ~/.mirage/config.yaml.
func ConfigPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ConfigDir, ConfigFile)
}

// MirageDir returns the absolute path to ~/.mirage/.
func MirageDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ConfigDir)
}

// Load reads and validates ~/.mirage/config.yaml.
// Returns ErrNotFound if the file does not exist yet (pre-init).
var ErrNotFound = errors.New("config not found: run `mirage init` first")

func Load() (*Config, error) {
	path := ConfigPath()
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config %s: %w", path, err)
	}

	if cfg.Version != CurrentVersion {
		return nil, fmt.Errorf("config version %q unsupported (want %q) — re-run `mirage init`", cfg.Version, CurrentVersion)
	}

	if err := validate(&cfg); err != nil {
		return nil, fmt.Errorf("invalid config: %w", err)
	}

	return &cfg, nil
}

// Save writes cfg to ~/.mirage/config.yaml with mode 0600.
func Save(cfg *Config) error {
	dir := MirageDir()
	if err := os.MkdirAll(dir, 0700); err != nil {
		return fmt.Errorf("create config dir %s: %w", dir, err)
	}

	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}

	path := ConfigPath()
	// Write atomically: temp file → rename.
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0600); err != nil {
		return fmt.Errorf("write config: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("save config: %w", err)
	}
	return nil
}

// Exists reports whether ~/.mirage/config.yaml exists.
func Exists() bool {
	_, err := os.Stat(ConfigPath())
	return err == nil
}

// validate checks required fields are populated.
func validate(cfg *Config) error {
	if cfg.Cloud == "" {
		return errors.New("cloud provider not set")
	}
	if cfg.Region == "" {
		return errors.New("region not set")
	}
	if cfg.Accounts.Hub.ID == "" {
		return errors.New("accounts.hub.id not set")
	}
	if cfg.Naming.Prefix == "" {
		return errors.New("naming.prefix not set")
	}
	for i, spoke := range cfg.Accounts.Spokes {
		if spoke.ID == "" {
			return fmt.Errorf("accounts.spokes[%d].id not set", i)
		}
		if spoke.Alias == "" {
			return fmt.Errorf("accounts.spokes[%d].alias not set", i)
		}
	}
	return nil
}

// GetSpoke returns the spoke config for a given alias or account ID.
func (c *Config) GetSpoke(aliasOrID string) (*SpokeAccount, error) {
	for i, s := range c.Accounts.Spokes {
		if s.Alias == aliasOrID || s.ID == aliasOrID {
			return &c.Accounts.Spokes[i], nil
		}
	}
	return nil, fmt.Errorf("spoke %q not found in config", aliasOrID)
}

// UpdateSpoke persists spoke changes back to the config.
func (c *Config) UpdateSpoke(spoke SpokeAccount) {
	for i, s := range c.Accounts.Spokes {
		if s.Alias == spoke.Alias {
			c.Accounts.Spokes[i] = spoke
			return
		}
	}
}
