#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${SPANK_REPO_URL:-https://github.com/nikolareljin/spank.git}"
CLONE_DIR="${SPANK_DIR:-spank}"
BIN_DIR="${SPANK_BIN_DIR:-$HOME/.local/bin}"
RUN_ARGS="${SPANK_RUN_ARGS:-run}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd git
need_cmd go
need_cmd install

if [[ -e "$CLONE_DIR/.git" ]]; then
  echo "Using existing repository at $CLONE_DIR"
else
  echo "Cloning $REPO_URL into $CLONE_DIR"
  git clone "$REPO_URL" "$CLONE_DIR"
fi

cd "$CLONE_DIR"

git submodule update --init --recursive

mkdir -p dist "$BIN_DIR"
echo "Building spank"
go build -o dist/spank ./cmd/spank

echo "Installing spank to $BIN_DIR/spank"
install -m 0755 dist/spank "$BIN_DIR/spank"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Warning: $BIN_DIR is not on PATH for this shell." >&2 ;;
esac

echo "Running: $BIN_DIR/spank $RUN_ARGS"
exec "$BIN_DIR/spank" $RUN_ARGS
