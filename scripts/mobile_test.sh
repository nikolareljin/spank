#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./mobile_install_deps.sh
source "$SCRIPTS_DIR/mobile_install_deps.sh"

if [[ "${SPANK_MOBILE_INSTALL_DEPS:-0}" == "1" ]]; then
  install_dependencies_spank_mobile
fi

cd "$MOBILE_DIR"
flutter pub get
flutter test
