#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cli.sh — unified CLI dispatcher for spank.
#
# Invoked as `./dev <command> [args]` and by the literal shortcut commands
# (./install ./update ./build ./run ./test ./deploy ./devices ./clean). It
# normalizes a shared argument surface and delegates to this repo's scripts/*.
# The Flutter mobile app lives in ./mobile; the Go CLI lives in ./cmd/spank.
#
# Shared params (every command):
#   [target]        android | ios | linux   (default: android)
#   --device <id>   target a specific device
#   --release       release build/run
#   -h, --help      show help
#
# iOS targets require macOS with Xcode (Apple's toolchain does not run on
# Linux/Windows) and fail fast with a clear message elsewhere.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$ROOT_DIR/mobile"

cmd="${1:-}"
[[ -n "$cmd" ]] && shift || true

usage() {
  cat <<EOF
Unified CLI — Spank (Flutter mobile app in ./mobile + Go CLI in ./cmd/spank)

Usage:
  ./dev <command> [target] [options]
  ./install ./update ./build ./run ./test ./deploy ./devices ./clean [options]

Commands:
  install            Install mobile deps + toolchain    (scripts/mobile_install_deps.sh)
  update             Sync git submodules                 (scripts/update_submodules.sh)
  build   [target]   Build the app artifact              (APK/IPA for mobile; binary for linux)
  run     [target]   Run on a device/emulator/host       (flutter run; or the Go CLI for linux)
  test    [target]   Run the test suite                  (flutter test; or 'go test' for linux)
  deploy  [target]   Build + install on a device         (android/ios)
  devices            List connected devices/emulators    (flutter devices)
  clean   [target]   Clean build outputs                 (flutter clean; go clean for linux)

Options (shared):
  target             android (default) | ios | linux    (alias: iphone -> ios)
  --device <id>      target a specific device
  --release          release build/run
  -h, --help         show this help

Notes:
  - iOS (build/run/deploy ios) requires macOS with Xcode; it fails fast on Linux/Windows.
  - linux targets the Go CLI (go build / go test / go run ./cmd/spank).
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
    iphone) TARGET="ios"; shift ;;            # legacy alias -> canonical 'ios'
    --device) DEVICE="${2:?--device needs an id}"; shift 2 ;;
    --release) RELEASE=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

target="${TARGET:-android}"

# macOS-only guard for iOS targets. Uses OSTYPE so the dispatcher stays dependency-free.
require_macos() {
  case "$OSTYPE" in
    darwin*) return 0 ;;
  esac
  echo "Target '$target' requires macOS with Xcode (Apple's toolchain does not run here)." >&2
  echo "Build/run/deploy iOS on a Mac, or use a macOS runner in CI." >&2
  exit 3
}

cd "$ROOT_DIR"

# --- delegation map ---------------------------------------------------------
case "$cmd" in
  install)
    exec bash scripts/mobile_install_deps.sh "${EXTRA[@]}"
    ;;
  update)
    exec bash scripts/update_submodules.sh "${EXTRA[@]}"
    ;;
  build)
    case "$target" in
      android)
        if [[ "$RELEASE" == 1 ]]; then
          exec bash scripts/mobile_build_release_apk.sh "${EXTRA[@]}"
        else
          exec bash scripts/mobile_build_debug_apk.sh "${EXTRA[@]}"
        fi
        ;;
      ios)
        require_macos
        exec bash scripts/mobile_build_ipa.sh "${EXTRA[@]}"
        ;;
      linux)
        exec bash scripts/build.sh "${EXTRA[@]}"
        ;;
    esac
    ;;
  run)
    case "$target" in
      android | ios)
        [[ "$target" == ios ]] && require_macos
        cd "$MOBILE_DIR"
        args=()
        [[ -n "$DEVICE" ]] && args+=(-d "$DEVICE")
        [[ "$RELEASE" == 1 ]] && args+=(--release)
        exec flutter run "${args[@]}" "${EXTRA[@]}"
        ;;
      linux)
        exec go run ./cmd/spank "${EXTRA[@]}"
        ;;
    esac
    ;;
  test)
    case "$target" in
      android | ios) exec bash scripts/mobile_test.sh "${EXTRA[@]}" ;;
      linux)         exec bash scripts/test.sh "${EXTRA[@]}" ;;
    esac
    ;;
  deploy)
    case "$target" in
      android)
        if [[ "$RELEASE" == 1 ]]; then
          echo "--release is not supported for 'deploy android' (mobile_install_device.sh installs a debug APK)." >&2
          exit 2
        fi
        if [[ -n "$DEVICE" ]]; then
          exec env ANDROID_SERIAL="$DEVICE" bash scripts/mobile_install_device.sh "${EXTRA[@]}"
        else
          exec bash scripts/mobile_install_device.sh "${EXTRA[@]}"
        fi
        ;;
      ios)
        require_macos
        env_vars=()
        [[ -n "$DEVICE" ]] && env_vars+=("FLUTTER_DEVICE=$DEVICE")
        [[ "$RELEASE" == 1 ]] && env_vars+=("SPANK_IOS_RELEASE=1")
        exec env "${env_vars[@]}" bash scripts/mobile_install_device_ios.sh "${EXTRA[@]}"
        ;;
      linux)
        echo "'deploy' is for mobile devices. For the Go CLI use './dev build linux' then run dist/spank, or package via CI." >&2
        exit 2
        ;;
    esac
    ;;
  devices)
    if [[ "$target" == linux ]]; then
      echo "The 'linux' (Go CLI) target has no devices; use './dev run linux'." >&2
      exit 0
    fi
    # flutter devices lists all attached mobile devices and needs no iOS toolchain
    # (on Linux it simply won't show iOS devices), so no macOS guard is applied.
    cd "$MOBILE_DIR"
    exec flutter devices "${EXTRA[@]}"
    ;;
  clean)
    case "$target" in
      linux)
        rm -rf "$ROOT_DIR/dist"
        exec go clean ./...
        ;;
      *)
        cd "$MOBILE_DIR"
        exec flutter clean
        ;;
    esac
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 2
    ;;
esac
