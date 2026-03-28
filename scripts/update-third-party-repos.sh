#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_DIR="${THIRD_PARTY_REPOS_DIR:-$ROOT_DIR/third_party/repos}"
DO_PULL=0
FOUND_REPO=0

usage() {
  cat <<'EOF'
Usage: scripts/update-third-party-repos.sh [--pull]

Batch-maintain git repositories under third_party/repos.

Options:
  --pull   After fetching, fast-forward each repo with git pull --ff-only
  -h, --help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pull)
      DO_PULL=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ ! -d "$REPOS_DIR" ]; then
  printf 'third-party repo directory not found: %s\n' "$REPOS_DIR"
  exit 0
fi

shopt -s nullglob
for repo in "$REPOS_DIR"/*; do
  [ -d "$repo/.git" ] || continue
  FOUND_REPO=1

  printf '==> %s\n' "${repo#$ROOT_DIR/}"
  git -C "$repo" fetch --all --prune --tags

  if [ "$DO_PULL" -eq 1 ]; then
    if git -C "$repo" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      git -C "$repo" pull --ff-only
    else
      printf 'No upstream configured for %s; skipped --pull\n' "$repo" >&2
    fi
  fi

  git -C "$repo" status -sb
done

if [ "$FOUND_REPO" -eq 0 ]; then
  printf 'No git repositories found under %s\n' "$REPOS_DIR"
fi
