#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./mobile_install_deps.sh
source "$SCRIPTS_DIR/mobile_install_deps.sh"

PACKAGE="com.nikolareljin.spankmobile"
ACTIVITY="$PACKAGE/io.flutter.embedding.android.FlutterActivity"
APK="$MOBILE_DIR/build/app/outputs/flutter-apk/app-debug.apk"

install_dependencies_spank_mobile

# Verify a device is reachable
if ! adb get-state >/dev/null 2>&1; then
  print_error "No Android device/emulator detected — connect a device or start an emulator."
  exit 1
fi

DEVICE_API=$(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '[:space:]')
log_info "Device API: $DEVICE_API"

log_info "Building debug APK..."
cd "$MOBILE_DIR"
flutter pub get
flutter build apk --debug

# Locate the Android SDK: prefer env vars, fall back to local.properties, then ~/Android/Sdk.
_sdk_dir() {
  [[ -n "${ANDROID_HOME:-}" ]] && echo "$ANDROID_HOME" && return
  [[ -n "${ANDROID_SDK_ROOT:-}" ]] && echo "$ANDROID_SDK_ROOT" && return
  local props="$MOBILE_DIR/android/local.properties"
  if [[ -f "$props" ]]; then
    local p; p=$(grep '^sdk.dir=' "$props" | cut -d= -f2-)
    [[ -n "$p" ]] && echo "$p" && return
  fi
  echo "$HOME/Android/Sdk"
}

SDK_DIR=$(_sdk_dir)
AAPT=$(find "$SDK_DIR/build-tools" -name "aapt" 2>/dev/null | sort -V | tail -1)

# Read the actual minSdk from the built APK — never hardcode a value that drifts with Flutter upgrades.
if [[ -n "$AAPT" ]]; then
  APK_MIN_SDK=$("$AAPT" dump badging "$APK" 2>/dev/null | grep -o "sdkVersion:'[0-9]*'" | grep -o "[0-9]*" || true)
  if [[ -n "$APK_MIN_SDK" && -n "$DEVICE_API" && "$DEVICE_API" -lt "$APK_MIN_SDK" ]]; then
    print_error "Device Android API $DEVICE_API is below the app's minSdkVersion $APK_MIN_SDK. Connect a device running API $APK_MIN_SDK or newer."
    exit 1
  fi
  [[ -n "$APK_MIN_SDK" ]] && log_info "APK minSdkVersion: $APK_MIN_SDK"
fi

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
