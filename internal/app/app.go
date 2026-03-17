package app

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"spank/internal/audio"
	"spank/internal/config"
	"spank/internal/detect"
	"spank/internal/sensor"
)

func Run(ctx context.Context, cfg config.Config) error {
	provider := sensor.NewIIOProvider(cfg.SysfsRoot, cfg.DmiRoot)
	info, err := sensor.FindSensor(ctx, provider, cfg.Sensor)
	if err != nil {
		return err
	}
	stream, err := provider.Open(ctx, info, cfg.SampleInterval)
	if err != nil {
		return err
	}

	detector := detect.New(cfg.Threshold, cfg.Cooldown)
	player := audio.Player{
		CommandTemplate: cfg.PlayerCmd,
		Volume:          cfg.Volume,
	}

	logf(cfg, "info", "monitoring sensor %s (%s) threshold=%.3f interval=%s cooldown=%s", info.ID, info.Path, cfg.Threshold, cfg.SampleInterval, cfg.Cooldown)

	ticker := time.NewTicker(cfg.SampleInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			sample, err := stream.Read(ctx)
			if err != nil {
				return fmt.Errorf("read sample from %s: %w", info.ID, err)
			}
			event, ok := detector.Process(info.ID, detect.Sample(sample))
			if !ok {
				continue
			}

			logf(cfg, "info", "impact detected sensor=%s severity=%.2f delta=%.3f", event.SensorID, event.Severity, event.Delta)
			if cfg.DryRun {
				continue
			}
			if err := player.Play(cfg.Sound); err != nil {
				return err
			}
		}
	}
}

func ListSensors(ctx context.Context, cfg config.Config) error {
	provider := sensor.NewIIOProvider(cfg.SysfsRoot, cfg.DmiRoot)
	sensors, err := provider.Discover(ctx)
	if err != nil {
		return err
	}
	if len(sensors) == 0 {
		return errors.New("no compatible Linux IIO accelerometers found")
	}

	for _, info := range sensors {
		fmt.Printf("%s\n", info.ID)
		fmt.Printf("  path: %s\n", info.Path)
		fmt.Printf("  name: %s\n", emptyFallback(info.Name))
		fmt.Printf("  label: %s\n", emptyFallback(info.Label))
		fmt.Printf("  location: %s\n", emptyFallback(info.Location))
		fmt.Printf("  scale: %.6f\n", info.Scale)
		fmt.Printf("  sample rate: %s\n", emptyFallback(info.SampleRate))
		fmt.Printf("  rank: %s\n\n", emptyFallback(info.RankReason))
	}
	return nil
}

func Doctor(ctx context.Context, cfg config.Config) error {
	provider := sensor.NewIIOProvider(cfg.SysfsRoot, cfg.DmiRoot)
	sensors, err := provider.Discover(ctx)
	if err != nil {
		fmt.Printf("sensor discovery: fail (%v)\n", err)
	} else {
		fmt.Printf("sensor discovery: ok (%d candidate(s))\n", len(sensors))
	}

	info, selectErr := sensor.FindSensor(ctx, provider, cfg.Sensor)
	if selectErr != nil {
		fmt.Printf("sensor selection: fail (%v)\n", selectErr)
	} else {
		fmt.Printf("sensor selection: ok (%s at %s)\n", info.ID, info.Path)
	}

	if cfg.DryRun {
		fmt.Println("audio check: skipped (dry-run enabled)")
		return selectErr
	}

	if err := audio.Check(); err != nil {
		fmt.Printf("audio check: fail (%v)\n", err)
	} else {
		player := cfg.PlayerCmd
		if strings.TrimSpace(player) == "" {
			player = audio.AvailableCommand()
		}
		fmt.Printf("audio check: ok (%s)\n", player)
	}
	return selectErr
}

func logf(cfg config.Config, level, format string, args ...any) {
	current := strings.ToLower(cfg.LogLevel)
	if current == "" {
		current = "info"
	}
	if current == "error" && level != "error" {
		return
	}
	if current == "info" && level == "debug" {
		return
	}
	fmt.Fprintf(os.Stderr, format+"\n", args...)
}

func emptyFallback(value string) string {
	if strings.TrimSpace(value) == "" {
		return "(none)"
	}
	return value
}
