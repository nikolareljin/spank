#!/usr/bin/env bash
# Build the spank mobile app and install it on a connected iPhone.
# Requires macOS with Xcode. This mirrors the Android mobile_install_device.sh flow.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./mobile_install_deps.sh
source "$SCRIPTS_DIR/mobile_install_deps.sh"

if [[ "$(get_os)" != "mac" ]]; then
  print_error "Installing to an iPhone requires macOS with Xcode. Use a Mac."
  exit 3
fi

if [[ "${SPANK_MOBILE_INSTALL_DEPS:-0}" == "1" ]]; then
  install_dependencies_spank_mobile
fi

cd "$MOBILE_DIR"
flutter pub get

# Target device: FLUTTER_DEVICE is set by cli.sh when --device <id> is passed;
# otherwise flutter picks the sole attached iOS device (and errors if ambiguous).
install_args=()
if [[ -n "${FLUTTER_DEVICE:-}" ]]; then
  install_args+=(-d "$FLUTTER_DEVICE")
fi

log_info "Building and installing on iPhone via 'flutter install'..."
flutter install "${install_args[@]}"
print_success "App installed on the iPhone. Launch it from the home screen (foreground monitoring on iOS)."
