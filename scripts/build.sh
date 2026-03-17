#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=./common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cd "$ROOT_DIR"
mkdir -p dist
log_info "building spank binary"
go build -o dist/spank ./cmd/spank
