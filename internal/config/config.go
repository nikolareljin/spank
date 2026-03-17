package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Sensor         string        `json:"sensor"`
	Threshold      float64       `json:"threshold"`
	SampleInterval time.Duration `json:"sample_interval"`
	Cooldown       time.Duration `json:"cooldown"`
	Sound          string        `json:"sound"`
	Volume         float64       `json:"volume"`
	PlayerCmd      string        `json:"player_cmd"`
	LogLevel       string        `json:"log_level"`
	DryRun         bool          `json:"dry_run"`
	SysfsRoot      string        `json:"-"`
	DmiRoot        string        `json:"-"`
}

type fileConfig struct {
	Sensor         string  `json:"sensor"`
	Threshold      float64 `json:"threshold"`
	SampleInterval string  `json:"sample_interval"`
	Cooldown       string  `json:"cooldown"`
	Sound          string  `json:"sound"`
	Volume         float64 `json:"volume"`
	PlayerCmd      string  `json:"player_cmd"`
	LogLevel       string  `json:"log_level"`
	DryRun         *bool   `json:"dry_run"`
}

func Default() Config {
	return Config{
		Threshold:      1.8,
		SampleInterval: 40 * time.Millisecond,
		Cooldown:       1200 * time.Millisecond,
		Sound:          "default",
		Volume:         1.0,
		LogLevel:       "info",
		SysfsRoot:      "/sys/bus/iio/devices",
		DmiRoot:        "/sys/class/dmi/id",
	}
}

func Load() (Config, error) {
	cfg := Default()

	if err := loadConfigFile(&cfg); err != nil {
		return Config{}, err
	}
	if err := applyEnv(&cfg); err != nil {
		return Config{}, err
	}
	return cfg, cfg.Validate()
}

func (c Config) Validate() error {
	switch {
	case c.Threshold <= 0:
		return errors.New("threshold must be greater than zero")
	case c.SampleInterval <= 0:
		return errors.New("sample interval must be greater than zero")
	case c.Cooldown < 0:
		return errors.New("cooldown cannot be negative")
	case c.Volume < 0:
		return errors.New("volume cannot be negative")
	}

	level := strings.ToLower(c.LogLevel)
	switch level {
	case "", "error", "info", "debug":
	default:
		return fmt.Errorf("invalid log level %q", c.LogLevel)
	}
	return nil
}

func ConfigPath() (string, error) {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "spank", "config.json"), nil
}

func loadConfigFile(cfg *Config) error {
	path, err := ConfigPath()
	if err != nil {
		return err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("read config file: %w", err)
	}

	var raw fileConfig
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("parse config file: %w", err)
	}

	if raw.Sensor != "" {
		cfg.Sensor = raw.Sensor
	}
	if raw.Threshold != 0 {
		cfg.Threshold = raw.Threshold
	}
	if raw.SampleInterval != "" {
		d, err := time.ParseDuration(raw.SampleInterval)
		if err != nil {
			return fmt.Errorf("parse config sample_interval: %w", err)
		}
		cfg.SampleInterval = d
	}
	if raw.Cooldown != "" {
		d, err := time.ParseDuration(raw.Cooldown)
		if err != nil {
			return fmt.Errorf("parse config cooldown: %w", err)
		}
		cfg.Cooldown = d
	}
	if raw.Sound != "" {
		cfg.Sound = raw.Sound
	}
	if raw.Volume != 0 {
		cfg.Volume = raw.Volume
	}
	if raw.PlayerCmd != "" {
		cfg.PlayerCmd = raw.PlayerCmd
	}
	if raw.LogLevel != "" {
		cfg.LogLevel = raw.LogLevel
	}
	if raw.DryRun != nil {
		cfg.DryRun = *raw.DryRun
	}
	return nil
}

func applyEnv(cfg *Config) error {
	if v := os.Getenv("SPANK_SENSOR"); v != "" {
		cfg.Sensor = v
	}
	if v := os.Getenv("SPANK_THRESHOLD"); v != "" {
		f, err := strconv.ParseFloat(v, 64)
		if err != nil {
			return fmt.Errorf("parse SPANK_THRESHOLD: %w", err)
		}
		cfg.Threshold = f
	}
	if v := os.Getenv("SPANK_SAMPLE_INTERVAL"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return fmt.Errorf("parse SPANK_SAMPLE_INTERVAL: %w", err)
		}
		cfg.SampleInterval = d
	}
	if v := os.Getenv("SPANK_COOLDOWN"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return fmt.Errorf("parse SPANK_COOLDOWN: %w", err)
		}
		cfg.Cooldown = d
	}
	if v := os.Getenv("SPANK_SOUND"); v != "" {
		cfg.Sound = v
	}
	if v := os.Getenv("SPANK_VOLUME"); v != "" {
		f, err := strconv.ParseFloat(v, 64)
		if err != nil {
			return fmt.Errorf("parse SPANK_VOLUME: %w", err)
		}
		cfg.Volume = f
	}
	if v := os.Getenv("SPANK_PLAYER_CMD"); v != "" {
		cfg.PlayerCmd = v
	}
	if v := os.Getenv("SPANK_LOG_LEVEL"); v != "" {
		cfg.LogLevel = v
	}
	if v := os.Getenv("SPANK_DRY_RUN"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			return fmt.Errorf("parse SPANK_DRY_RUN: %w", err)
		}
		cfg.DryRun = b
	}
	return nil
}
