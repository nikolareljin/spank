#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./mobile_install_deps.sh
source "$SCRIPTS_DIR/mobile_install_deps.sh"

PACKAGE="com.nikolareljin.spankmobile"
ACTIVITY="$PACKAGE/io.flutter.embedding.android.FlutterActivity"
APK="$MOBILE_DIR/build/app/outputs/flutter-apk/app-debug.apk"
MIN_SDK=21  # Flutter's minimum supported Android API level

install_dependencies_spank_mobile

# Verify a device is reachable
if ! adb get-state >/dev/null 2>&1; then
  print_error "No Android device/emulator detected — connect a device or start an emulator."
  exit 1
fi

# Check device API level before building
DEVICE_API=$(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '[:space:]')
if [[ -n "$DEVICE_API" && "$DEVICE_API" -lt "$MIN_SDK" ]]; then
  print_error "Device Android API $DEVICE_API is below the minimum required API $MIN_SDK. Connect a newer device (Android 5.0+)."
  exit 1
fi
log_info "Device API: $DEVICE_API (minimum: $MIN_SDK)"

log_info "Building debug APK..."
cd "$MOBILE_DIR"
flutter pub get
flutter build apk --debug

log_info "Installing $APK..."
INSTALL_OUT=$(adb install -r "$APK" 2>&1)
echo "$INSTALL_OUT"
if echo "$INSTALL_OUT" | grep -q "^Failure"; then
  print_error "APK install failed."
  exit 1
fi

log_info "Launching $PACKAGE..."
adb shell am start -n "$ACTIVITY"

print_success "App installed and launched."
