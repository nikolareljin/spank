#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cli.sh — unified mobile CLI dispatcher.
#
# Invoked as `./dev <command> [args]` (uniform across every game repo) and by the
# literal shortcut commands. It normalizes a SHARED argument surface and delegates
# to this repo's existing scripts/* (the Flutter mobile app lives in ./mobile).
# Same command names + params across time-loop-ar, lexiweave, bloombounce-orchard
# and spank; only this delegation map differs (here: spank mobile / Flutter).
#
# Shared params (every command):
#   [target]        android | ios | linux   (default: android)
#   --device <id>   target a specific device
#   --release       release build/run
#   -h, --help      show help
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"

cmd="${1:-}"
[[ -n "$cmd" ]] && shift || true

usage() {
  cat <<EOF
Unified CLI — Spank (mobile app: Flutter in ./mobile)

Usage:
  ./dev <command> [target] [options]     # uniform entry (works in every game repo)
  ./install ./build ./run ./test ./deploy ./devices ./clean [options]   # literal shortcuts

Commands:
  install            Install mobile deps + toolchain   (scripts/mobile_install_deps.sh)
  build   [android]  Build the APK                      (scripts/mobile_build_*_apk.sh)
  run     [android]  Run on a device/emulator           (flutter run in ./mobile)
  test               Run the mobile test suite          (scripts/mobile_test.sh)
  deploy  [android]  Build + install on a device        (build + scripts/mobile_install_device.sh)
  devices            List connected devices/emulators   (flutter devices)
  clean              Clean build outputs                (flutter clean in ./mobile)

Options (shared):
  target             android (default). ios/linux are not supported by the mobile scripts.
  --device <id>      target a specific device
  --release          release build/run (build/run)
  -h, --help         show this help
EOF
}

if [[ -z "$cmd" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
  usage
  exit 0
fi

# --- shared argument parsing ------------------------------------------------
TARGET=""
DEVICE=""
RELEASE=0
declare -a EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    android | ios | linux) TARGET="$1"; shift ;;
    --device) DEVICE="${2:?--device needs an id}"; shift 2 ;;
    --release) RELEASE=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

target="${TARGET:-android}"

require_android() {
  [[ "$target" == android ]] && return 0
  echo "spank mobile only supports the 'android' target for '$cmd' (got '$target')." >&2
  exit 2
}

cd "$ROOT_DIR"

# --- delegation map (spank mobile / Flutter) --------------------------------
case "$cmd" in
  install)
    exec bash scripts/mobile_install_deps.sh "${EXTRA[@]}"
    ;;
  build)
    require_android
    if [[ "$RELEASE" == 1 ]]; then
      exec bash scripts/mobile_build_release_apk.sh "${EXTRA[@]}"
    else
      exec bash scripts/mobile_build_debug_apk.sh "${EXTRA[@]}"
    fi
    ;;
  run)
    cd "$MOBILE_DIR"
    args=()
    [[ -n "$DEVICE" ]] && args+=(-d "$DEVICE")
    [[ "$RELEASE" == 1 ]] && args+=(--release)
    exec flutter run "${args[@]}" "${EXTRA[@]}"
    ;;
  test)
    exec bash scripts/mobile_test.sh "${EXTRA[@]}"
    ;;
  deploy)
    require_android
    bash scripts/mobile_build_debug_apk.sh
    exec bash scripts/mobile_install_device.sh "${EXTRA[@]}"
    ;;
  devices)
    cd "$MOBILE_DIR"
    exec flutter devices "${EXTRA[@]}"
    ;;
  clean)
    cd "$MOBILE_DIR"
    exec flutter clean
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 2
    ;;
esac
