# Changelog

## [Unreleased]

## [0.3.0] - 2026-04-26

- Added Android background **Call Mode**: a foreground service keeps monitoring active when the app is backgrounded during a call.
- Added **Private** audio routing: sound plays through the earpiece only; other call participants cannot hear it.
- Added **Shared** audio routing: sound plays through the loudspeaker so the call microphone picks it up, letting other participants hear it.
- Added Call Mode toggle and Audio Mode segmented button (Private / Shared) to the Settings card in the mobile UI.
- Added `POST_NOTIFICATIONS` runtime permission request on Android 13+ to show the required foreground service notification.
- On Android 12+ (API 31), audio routing uses `setCommunicationDevice` / `clearCommunicationDevice` instead of the deprecated `isSpeakerphoneOn`.
- Added Flutter mobile CI checks for formatting, analysis, widget tests, and debug APK build on pushes and pull requests.
- Added a release APK GitHub Actions workflow that builds and attaches the Android release APK on auto-tagged `release/X.Y.Z → main` merges.
- Switched the release tag gate workflow to the reusable `ci-helpers` release-tag check.

## [0.2.0] - 2026-03-17

- Added `setup.sh` for one-step clone, build, install, and immediate run on the local machine.
- Added a one-line install command near the top of `README.md`.
- Imported the upstream MIT-licensed `pain`, `halo`, and `sexy` MP3 sound packs from `taigrr/spank`.

## [0.1.0] - 2026-03-17

- Initial Linux-first `spank` release with Go CLI commands for `run`, `list-sensors`, and `doctor`.
- Added Linux IIO accelerometer discovery and polling with Lenovo-friendly ranking heuristics and manual sensor overrides.
- Added movement detection, sound playback, XDG config loading, and a sample `systemd --user` service.
- Added shared script helpers, CI workflows, release-tag checks, and auto-tag integration.
