#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/create_production.sh -t <tag> [--name <name>] [--remote <name>] [--repo <path>] [--fetch-tags]
EOF
}

log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

tag=""
prod_tag="production"
remote="origin"
repo_dir="${GITHUB_WORKSPACE:-$(pwd)}"
fetch_tags=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag) tag="$2"; shift 2;;
    --name|--tag-name|--branch) prod_tag="$2"; shift 2;;
    --remote) remote="$2"; shift 2;;
    --repo) repo_dir="$2"; shift 2;;
    --fetch-tags) fetch_tags=true; shift;;
    -h|--help) usage; exit 0;;
    *) log_error "Unknown argument: $1"; usage; exit 2;;
  esac
done

if [[ -z "$tag" ]]; then
  log_error "Tag is required (-t <tag>)"
  usage
  exit 2
fi

if $fetch_tags; then
  git -C "$repo_dir" fetch --tags --prune --force >/dev/null 2>&1 || true
fi

if ! git -C "$repo_dir" rev-parse "refs/tags/$tag" >/dev/null 2>&1; then
  log_error "Tag $tag not found in $repo_dir"
  exit 1
fi

log_info "Updating ${prod_tag} tag to ${tag}"
git -C "$repo_dir" tag -f "$prod_tag" "$tag"
git -C "$repo_dir" push "$remote" "refs/tags/${prod_tag}:refs/tags/${prod_tag}" --force-with-lease
log_info "Production tag ${prod_tag} now points to ${tag}"
