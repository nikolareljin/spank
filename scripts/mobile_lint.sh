#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./mobile_install_deps.sh
source "$SCRIPTS_DIR/mobile_install_deps.sh"

install_dependencies_spank_mobile

cd "$MOBILE_DIR"
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
