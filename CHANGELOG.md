# Changelog

## [0.2.0] - 2026-03-17

- Added `setup.sh` for one-step clone, build, install, and immediate run on the local machine.
- Added a one-line install command near the top of `README.md`.
- Imported the upstream MIT-licensed `pain`, `halo`, and `sexy` MP3 sound packs from `taigrr/spank`.

## [0.1.0] - 2026-03-17

- Initial Linux-first `spank` release with Go CLI commands for `run`, `list-sensors`, and `doctor`.
- Added Linux IIO accelerometer discovery and polling with Lenovo-friendly ranking heuristics and manual sensor overrides.
- Added movement detection, sound playback, XDG config loading, and a sample `systemd --user` service.
- Added shared script helpers, CI workflows, release-tag checks, and auto-tag integration.
