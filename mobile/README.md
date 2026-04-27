# Spank Mobile

`mobile/` is the Flutter app that adapts `spank` to phones so older Android devices and supported iPhones can act as dedicated tap or slap triggered sound devices.

## Behavior

The detector matches the Go implementation:

- compute acceleration magnitude from `x`, `y`, and `z`
- initialize the baseline from the first sample
- update the baseline with `alpha = 0.18`
- trigger when `abs(magnitude - baseline) >= threshold`
- suppress repeated triggers during cooldown

Dart owns the detector and sound-pack selection. Native Android and iOS code only provide:

- accelerometer samples
- persisted settings
- playback for bundled MP3 assets

## Run

```bash
flutter pub get
flutter test
flutter run -d android
```

## Platform notes

- Android target: `minSdk 21`
- iPhone target: `iOS 12+`
- Android supports background monitoring via **Call Mode** (foreground service + `POST_NOTIFICATIONS` permission on API 33+)
- iPhone monitoring is foreground-only
- Sound assets are copied from `../internal/audio/assets/`

For full device setup and build instructions, see [`../docs/mobile-build-run.md`](../docs/mobile-build-run.md).
