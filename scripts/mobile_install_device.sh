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

log_info "Building debug APK..."
cd "$MOBILE_DIR"
flutter pub get
flutter build apk --debug

log_info "Installing $APK..."
adb install -r "$APK"

log_info "Launching $PACKAGE..."
adb shell am start -n "$ACTIVITY"

print_success "App installed and launched."
