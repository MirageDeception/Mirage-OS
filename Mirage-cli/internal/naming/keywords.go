// Package naming — keywords.go
// Manages the naming keywords file used to generate realistic-sounding
// deception resource names. Ships a default embedded keyword list;
// operators can override with their own file via --keywords-file or config.
package naming

import (
	_ "embed"
	"fmt"
	"math/rand"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

//go:embed keywords.yaml
var defaultKeywordsYAML []byte

// Keywords holds word lists used for realistic resource name generation.
type Keywords struct {
	Prefixes     []string `yaml:"prefixes"`
	Teams        []string `yaml:"teams"`
	Environments []string `yaml:"environments"`
}

// LoadKeywords loads keywords from the given file path.
// If path is empty, returns the embedded default keywords.
func LoadKeywords(path string) (*Keywords, error) {
	var data []byte
	if path == "" {
		data = defaultKeywordsYAML
	} else {
		var err error
		data, err = os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read keywords file %q: %w", path, err)
		}
	}

	var kw Keywords
	if err := yaml.Unmarshal(data, &kw); err != nil {
		return nil, fmt.Errorf("parse keywords file: %w", err)
	}

	if len(kw.Prefixes) == 0 {
		return nil, fmt.Errorf("keywords file must have at least one entry under 'prefixes'")
	}

	return &kw, nil
}

// RandomPrefix returns a random prefix from the keywords list.
func (k *Keywords) RandomPrefix() string {
	if len(k.Prefixes) == 0 {
		return "corp"
	}
	r := rand.New(rand.NewSource(time.Now().UnixNano())) //nolint:gosec
	return k.Prefixes[r.Intn(len(k.Prefixes))]
}

// DefaultKeywordsPath returns "" to signal use of embedded defaults.
// Operators can set naming.keywords_file in config to override.
func DefaultKeywordsPath() string {
	return ""
}
