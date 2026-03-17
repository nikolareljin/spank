package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLoadPrecedence(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", tmp)
	configDir := filepath.Join(tmp, "spank")
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(configDir, "config.json"), []byte(`{
		"threshold": 2.5,
		"sample_interval": "100ms",
		"dry_run": false
	}`), 0o644); err != nil {
		t.Fatal(err)
	}

	t.Setenv("SPANK_THRESHOLD", "3.5")
	t.Setenv("SPANK_DRY_RUN", "true")

	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Threshold != 3.5 {
		t.Fatalf("threshold = %v", cfg.Threshold)
	}
	if cfg.SampleInterval != 100*time.Millisecond {
		t.Fatalf("sample interval = %v", cfg.SampleInterval)
	}
	if !cfg.DryRun {
		t.Fatal("dry run should be true from env override")
	}
}

func TestValidateRejectsInvalidValues(t *testing.T) {
	cfg := Default()
	cfg.Threshold = 0
	if err := cfg.Validate(); err == nil {
		t.Fatal("expected threshold validation error")
	}
}
