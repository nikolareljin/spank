# Repository Guidelines

## Project Structure & Module Organization
`spank` is a small Go CLI. The entrypoint lives in `cmd/spank/main.go`. Core packages are under `internal/`: `app` wires commands together, `config` loads and validates settings, `detect` handles motion detection, `sensor` reads Linux IIO accelerometers, and `audio` manages playback. Build artifacts go to `dist/`. Operational assets live in `packaging/` such as `packaging/spank.service`. Contributor scripts live in `scripts/`. The vendored helper repo in `scripts/script-helpers/` has its own local guidance; treat it as separate unless your change explicitly targets it.

## Build, Test, and Development Commands
Use the scripted entrypoints first because CI runs them.

- `./scripts/build.sh`: builds `dist/spank`.
- `./scripts/test.sh`: runs `go test ./...`.
- `./scripts/lint.sh`: checks formatting with `gofmt -l cmd internal` and runs `go vet ./...`.
- `go build ./cmd/spank`: quick local compile when you do not need the `dist/` output.
- `./dist/spank doctor` or `go run ./cmd/spank doctor`: verify Linux sensor and audio readiness.

If CI-like behavior matters, run `./scripts/update_submodules.sh` before lint, test, or build.

## Coding Style & Naming Conventions
Follow standard Go style: tabs for indentation, exported identifiers in `CamelCase`, package-local names in `camelCase`, and short, focused packages under `internal/`. Let `gofmt` define formatting; do not hand-align code. Keep CLI command names and flags lowercase with hyphenated forms such as `list-sensors` and `--sample-interval`. Shell scripts should remain Bash with `set -euo pipefail`.

## Testing Guidelines
Tests are standard Go `_test.go` files beside the code they cover, for example `internal/detect/detector_test.go`. Add table-driven tests for config parsing, detection thresholds, and Linux sensor heuristics when behavior changes. Run `./scripts/test.sh` before opening a PR. Run `./scripts/lint.sh` too, since formatting failures are enforced.

## Commit & Pull Request Guidelines
Recent history uses concise Conventional Commit prefixes: `feat:`, `fix:`, `docs:`, and `chore:`. Keep subjects imperative and specific, for example `fix: handle missing IIO scale file`. PRs should explain user-visible behavior, note Linux hardware assumptions, link related issues, and include terminal output or screenshots when changing diagnostics or install/setup flows. Release branches follow `release/<version>`, and CI will check tag availability for them.

## Security & Configuration Tips
This project reads from `/sys/bus/iio/devices` and shells out to an audio player. Avoid broadening supported command templates or config inputs without validating them carefully. Document any new environment variables in `README.md` and keep config precedence consistent: defaults, config file, environment, then CLI flags.
