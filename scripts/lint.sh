#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=./common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cd "$ROOT_DIR"
log_info "running gofmt check"
test -z "$(gofmt -l cmd internal)"

log_info "running go vet"
go vet ./...
