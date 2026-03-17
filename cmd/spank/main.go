package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"spank/internal/app"
	"spank/internal/config"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := run(ctx, os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "spank: %v\n", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string) error {
	command := "run"
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		command = args[0]
		args = args[1:]
	}

	cfg, err := parseConfig(args)
	if err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}

	switch command {
	case "run":
		return app.Run(ctx, cfg)
	case "list-sensors":
		return app.ListSensors(ctx, cfg)
	case "doctor":
		return app.Doctor(ctx, cfg)
	case "help":
		printUsage()
		return nil
	default:
		printUsage()
		return fmt.Errorf("unknown command %q", command)
	}
}

func parseConfig(args []string) (config.Config, error) {
	cfg, err := config.Load()
	if err != nil {
		return config.Config{}, err
	}

	fs := flag.NewFlagSet("spank", flag.ContinueOnError)
	fs.SetOutput(os.Stdout)
	fs.StringVar(&cfg.Sensor, "sensor", cfg.Sensor, "sensor path or device name override")
	fs.Float64Var(&cfg.Threshold, "threshold", cfg.Threshold, "trigger threshold on normalized acceleration delta")
	fs.DurationVar(&cfg.SampleInterval, "sample-interval", cfg.SampleInterval, "accelerometer poll interval")
	fs.DurationVar(&cfg.Cooldown, "cooldown", cfg.Cooldown, "minimum delay between triggers")
	fs.StringVar(&cfg.Sound, "sound", cfg.Sound, "sound asset name")
	fs.Float64Var(&cfg.Volume, "volume", cfg.Volume, "volume multiplier")
	fs.StringVar(&cfg.PlayerCmd, "player-cmd", cfg.PlayerCmd, "external player command template; use %s for file path")
	fs.StringVar(&cfg.LogLevel, "log-level", cfg.LogLevel, "log verbosity: error, info, debug")
	fs.BoolVar(&cfg.DryRun, "dry-run", cfg.DryRun, "log trigger events without playing sound")
	fs.Usage = printUsage
	if err := fs.Parse(args); err != nil {
		return config.Config{}, err
	}

	if err := cfg.Validate(); err != nil {
		return config.Config{}, err
	}
	return cfg, nil
}

func printUsage() {
	fmt.Println(`Usage:
  spank [command] [flags]

Commands:
  run           monitor the accelerometer and react to sudden movement
  list-sensors  list discovered Linux IIO accelerometers
  doctor        inspect sensor and audio readiness
  help          show this help

Flags:
  --sensor
  --threshold
  --sample-interval
  --cooldown
  --sound
  --volume
  --player-cmd
  --log-level
  --dry-run`)
}
