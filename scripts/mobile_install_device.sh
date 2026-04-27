#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./mobile_install_deps.sh
source "$SCRIPTS_DIR/mobile_install_deps.sh"

PACKAGE="com.nikolareljin.spankmobile"
ACTIVITY="$PACKAGE/.MainActivity"
APK="$MOBILE_DIR/build/app/outputs/flutter-apk/app-debug.apk"

install_dependencies_spank_mobile

# Verify exactly one device is reachable (or the one named by ANDROID_SERIAL).
_connected_devices() {
  adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1 }'
}
CONNECTED_DEVICES=$(_connected_devices)
DEVICE_COUNT=$(printf '%s\n' "$CONNECTED_DEVICES" | grep -c . || true)
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  if ! printf '%s\n' "$CONNECTED_DEVICES" | grep -Fxq "$ANDROID_SERIAL"; then
    print_error "Device '$ANDROID_SERIAL' (ANDROID_SERIAL) not found. Connected: ${CONNECTED_DEVICES:-none}"
    exit 1
  fi
elif [[ "$DEVICE_COUNT" -eq 0 ]]; then
  print_error "No Android device/emulator detected — connect a device or start an emulator."
  exit 1
elif [[ "$DEVICE_COUNT" -gt 1 ]]; then
  print_error "Multiple devices detected — set ANDROID_SERIAL to choose one:\n$CONNECTED_DEVICES"
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

_version_ge() {
  local IFS=.
  local -a l r
  read -r -a l <<< "$1"
  read -r -a r <<< "$2"
  local i
  for ((i = 0; i < ${#l[@]} || i < ${#r[@]}; i++)); do
    local lv=${l[i]:-0} rv=${r[i]:-0}
    ((10#$lv > 10#$rv)) && return 0
    ((10#$lv < 10#$rv)) && return 1
  done
  return 0
}

_latest_aapt() {
  local sdk_dir="$1" best_ver="" best_aapt="" dir version candidate
  for dir in "$sdk_dir"/build-tools/*/; do
    [[ -d "$dir" ]] || continue
    candidate="${dir}aapt"
    [[ -f "$candidate" ]] || continue
    version=$(basename "$dir")
    if [[ -z "$best_ver" ]] || _version_ge "$version" "$best_ver"; then
      best_ver="$version"
      best_aapt="$candidate"
    fi
  done
  [[ -n "$best_aapt" ]] && echo "$best_aapt"
}

SDK_DIR=$(_sdk_dir)
AAPT=$(_latest_aapt "$SDK_DIR")

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
if INSTALL_OUT=$(adb install -r "$APK" 2>&1); then
  INSTALL_STATUS=0
else
  INSTALL_STATUS=1
fi
echo "$INSTALL_OUT"
if [[ "$INSTALL_STATUS" -ne 0 ]] || echo "$INSTALL_OUT" | grep -q "^Failure"; then
  print_error "APK install failed."
  exit 1
fi

log_info "Launching $PACKAGE..."
adb shell am start -n "$ACTIVITY"

print_success "App installed and launched."
