#!/usr/bin/env bash
# Install all dependencies required to build and deploy the spank mobile app.
# Sourceable: when sourced, exposes install_dependencies_spank_mobile().
# When executed directly, installs all deps immediately.
# Safe to run repeatedly — skips tools that are already present.
set -euo pipefail

# shellcheck source=./common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

shlib_import deps os

_spank_need() { ! command -v "$1" >/dev/null 2>&1; }

install_dependencies_spank_mobile() {
  local os; os=$(get_os)

  # git
  if _spank_need git; then
    log_info "Installing git..."
    case "$os" in
      linux) install_dependencies git ;;
      mac)   brew install git ;;
      *)     print_error "Unsupported OS '$os'. Install git manually."; return 1 ;;
    esac
  else
    log_info "git: $(git --version)"
  fi

  # go
  if _spank_need go; then
    log_info "Installing Go..."
    case "$os" in
      linux) install_dependencies golang-go ;;
      mac)   brew install go ;;
      *)     print_error "Unsupported OS '$os'. Install Go manually."; return 1 ;;
    esac
  else
    log_info "Go: $(go version)"
  fi

  # adb
  if _spank_need adb; then
    log_info "Installing ADB (Android platform tools)..."
    case "$os" in
      linux) install_dependencies android-tools-adb ;;
      mac)   brew install android-platform-tools ;;
      *)     print_error "Unsupported OS '$os'. Install ADB manually."; return 1 ;;
    esac
  else
    log_info "ADB: $(adb --version | head -1)"
  fi

  # flutter
  if _spank_need flutter; then
    log_info "Installing Flutter SDK..."
    case "$os" in
      linux)
        if command -v snap >/dev/null 2>&1; then
          run_with_optional_sudo true snap install flutter --classic
        else
          print_error "snap not found. Install Flutter manually: https://docs.flutter.dev/get-started/install/linux"
          return 1
        fi
        ;;
      mac)
        brew install --cask flutter
        ;;
      *)
        print_error "Unsupported OS '$os'. Install Flutter manually: https://docs.flutter.dev/get-started/install"
        return 1
        ;;
    esac
  else
    log_info "Flutter: $(flutter --version 2>/dev/null | head -1)"
  fi

  print_success "All spank mobile dependencies are installed."
}

# Run when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_dependencies_spank_mobile
fi
