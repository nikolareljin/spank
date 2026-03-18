# Mobile Build And Run

This guide covers the Flutter mobile app in [`../mobile/`](../mobile/).

## Overview

The mobile app reuses the same detector behavior as the Go version:

- magnitude from `x`, `y`, `z`
- baseline initialized from the first sample
- rolling baseline with `alpha = 0.18`
- trigger on `abs(magnitude - baseline) >= threshold`
- cooldown suppression between hits

Use it to turn older phones into dedicated tap or slap triggered sound devices.

## Requirements

- Flutter SDK installed and on `PATH`
- Android Studio or Android SDK tools for Android builds
- Xcode for iPhone builds
- A connected Android phone or iPhone, or a simulator/emulator

Current mobile targets:

- Android `minSdk 21`
- iPhone `iOS 12+`

## Common setup

```bash
cd /path/to/spank/mobile
flutter pub get
flutter test
```

Optional checks:

```bash
flutter devices
flutter doctor
```

## Build And Run On Android

1. Connect an Android phone with developer options and USB debugging enabled.
2. Confirm the device is visible:

```bash
flutter devices
```

3. Run the app in debug mode:

```bash
flutter run -d android
```

4. Build a debug APK for direct install:

```bash
flutter build apk --debug
```

5. Build a release APK:

```bash
flutter build apk --release
```

Typical output:

- `build/app/outputs/flutter-apk/app-debug.apk`
- `build/app/outputs/flutter-apk/app-release.apk`

Notes:

- The app uses the device accelerometer directly, so test on real hardware rather than an emulator.
- Older Android phones may need threshold tuning from the in-app settings or preset chips.

## Build And Run On iPhone

iPhone builds must be done on macOS with Xcode installed.

1. Open the mobile app directory:

```bash
cd /path/to/spank/mobile
```

2. Fetch Flutter dependencies:

```bash
flutter pub get
```

3. Open the iOS project in Xcode if you need signing setup:

```bash
open ios/Runner.xcworkspace
```

4. Configure Apple signing in Xcode for the `Runner` target.
5. Connect the iPhone and trust the development machine.
6. Run from Flutter:

```bash
flutter run -d ios
```

7. Build an iOS release artifact:

```bash
flutter build ios --release
```

Notes:

- The current deployment target is iOS 12+.
- Use a physical iPhone for sensor validation. The simulator is not useful for tap detection.
- iOS keeps monitoring in the foreground only in this version.

## Using The App

1. Launch the app on the phone.
2. Tap `Arm` to start monitoring the accelerometer.
3. Tap or slap the phone to test detection.
4. Use `Preview Sound` to verify audio output.
5. Adjust `Threshold`, `Cooldown`, `Volume`, and `Sound Pack` as needed.
6. Use `Dry run` if you want to tune detection without playing sound.

## Troubleshooting

- No sound:
  - Check the phone volume.
  - Use `Preview Sound` first to verify playback works.
- Too many triggers:
  - Increase `Threshold`.
  - Increase `Cooldown`.
- Missed triggers:
  - Lower `Threshold`.
  - Remove heavy cases or mounts that dampen impact.
- iPhone build fails:
  - Recheck signing and provisioning in Xcode.
  - Confirm the target device is running iOS 12 or newer.
- Android install fails:
  - Confirm USB debugging is enabled.
  - If sideloading an APK, allow installs from unknown sources on the device.
