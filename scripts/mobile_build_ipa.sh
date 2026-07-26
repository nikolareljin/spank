#!/usr/bin/env bash
# Build a release iOS .ipa for the spank mobile app.
# Requires macOS with Xcode — Apple's toolchain does not run on Linux/Windows.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./mobile_install_deps.sh
# Sourcing sets MOBILE_DIR, imports logging + os helpers (get_os, print_*, log_*).
source "$SCRIPTS_DIR/mobile_install_deps.sh"

if [[ "$(get_os)" != "mac" ]]; then
  print_error "Building iOS requires macOS with Xcode. Build on a Mac or in CI on a macOS runner."
  exit 3
fi

if [[ "${SPANK_MOBILE_INSTALL_DEPS:-0}" == "1" ]]; then
  install_dependencies_spank_mobile
fi

cd "$MOBILE_DIR"
flutter pub get

EXPORT_OPTS="$MOBILE_DIR/ios/ExportOptions.plist"
if [[ -f "$EXPORT_OPTS" ]]; then
  log_info "Building signed release IPA with ios/ExportOptions.plist..."
  flutter build ipa --release --export-options-plist "$EXPORT_OPTS"
  print_success "IPA built under build/ios/ipa/."
else
  print_warning "No ios/ExportOptions.plist found — producing an UNSIGNED archive only."
  print_warning "For a distributable IPA: sign via 'fastlane ios ios_release', or copy"
  print_warning "ios/ExportOptions.plist.example to ios/ExportOptions.plist and set your team id."
  flutter build ios --release --no-codesign
  print_success "Unsigned iOS build complete (not exportable to the App Store as-is)."
fi
