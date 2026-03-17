# spank

`spank` is a Linux-first port of [`taigrr/spank`](https://github.com/taigrr/spank) for laptop accelerometers on Ubuntu/Linux, validated around Lenovo-style hardware but designed to stay portable across other brands that expose sensors through the Linux IIO stack.

The core behavior is simple: monitor a laptop accelerometer, detect sudden motion, and play a sound.

## Current support

- Linux only
- Raw accelerometers exposed through `/sys/bus/iio/devices/iio:device*`
- Lenovo-friendly discovery heuristics with manual sensor override for other brands
- CLI commands for monitoring, diagnostics, and sensor listing
- Sample `systemd --user` unit for login-time autostart

## Why IIO instead of orientation services

Linux desktop orientation helpers such as `iio-sensor-proxy` are useful for screen rotation, but they do not provide the continuous raw XYZ acceleration stream needed for impact detection. `spank` reads the kernel IIO/sysfs interface directly.

## Commands

```bash
spank run
spank list-sensors
spank doctor
```

## Quick start

```bash
cd /projects/Projects/_NIK_PROGRAMS/spank
go build ./cmd/spank
./spank doctor
./spank list-sensors
./spank run --dry-run
```

If auto-detection picks the wrong device:

```bash
./spank run --sensor /sys/bus/iio/devices/iio:device0
```

## Configuration

Configuration is loaded in this order:

1. Built-in defaults
2. Config file at `$XDG_CONFIG_HOME/spank/config.json` or `~/.config/spank/config.json`
3. Environment variables
4. CLI flags

Supported settings:

- `sensor`
- `threshold`
- `sample_interval`
- `cooldown`
- `sound`
- `volume`
- `player_cmd`
- `log_level`
- `dry_run`

Environment variable forms:

```bash
SPANK_SENSOR=/sys/bus/iio/devices/iio:device0
SPANK_THRESHOLD=1.8
SPANK_SAMPLE_INTERVAL=40ms
SPANK_COOLDOWN=1200ms
SPANK_SOUND=default
SPANK_VOLUME=1.0
SPANK_PLAYER_CMD="paplay %s"
SPANK_LOG_LEVEL=debug
SPANK_DRY_RUN=true
```

## systemd user service

Copy the sample unit:

```bash
mkdir -p ~/.config/systemd/user
cp packaging/spank.service ~/.config/systemd/user/spank.service
systemctl --user daemon-reload
systemctl --user enable --now spank.service
```

Adjust the `ExecStart` path and flags in the unit file as needed.

## Linux notes

- Most laptops that work will expose a 3-axis accelerometer under `/sys/bus/iio/devices`.
- Access to the sysfs files is usually readable as an unprivileged user; if not, `spank doctor` will show the failure.
- Some laptops expose multiple motion sensors. `spank list-sensors` shows ranking reasons and helps choose the correct one.
- If no suitable accelerometer exists, `spank` exits cleanly with a diagnostic instead of pretending support.

## Development

```bash
go test ./...
go build ./cmd/spank
```
