#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESTRICTED_DIR="${RESTRICTED_DIR:-$ROOT_DIR/restricted}"
OPENCLAW_SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-$HOME/.openclaw/skills}"
DO_DELETE=1
SKILLS=()

usage() {
  cat <<'EOF'
Usage: scripts/sync-restricted-skills.sh [--skill <name>]... [--no-delete]

Copy restricted local skills into the OpenClaw local override directory.

Options:
  --skill <name>  Sync only the named skill. Repeat to sync multiple skills.
  --no-delete     Keep destination-only files instead of removing them.
  -h, --help

Environment:
  RESTRICTED_DIR       Source directory. Default: <repo>/restricted
  OPENCLAW_SKILLS_DIR  Target directory. Default: ~/.openclaw/skills
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skill)
      [ "$#" -ge 2 ] || {
        printf 'Missing value for --skill\n' >&2
        usage >&2
        exit 1
      }
      SKILLS+=("$2")
      shift
      ;;
    --no-delete)
      DO_DELETE=0
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

if [ "${#SKILLS[@]}" -eq 0 ]; then
  SKILLS=(docx xlsx pdf pptx)
fi

if [ ! -d "$RESTRICTED_DIR" ]; then
  printf 'restricted source directory not found: %s\n' "$RESTRICTED_DIR" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  printf 'rsync is required but was not found in PATH\n' >&2
  exit 1
fi

mkdir -p "$OPENCLAW_SKILLS_DIR"

RSYNC_ARGS=(
  -a
  --exclude=.git/
  --exclude=.venv/
  --exclude=.pytest_cache/
  --exclude=__pycache__/
  --exclude=*.pyc
)

if [ "$DO_DELETE" -eq 1 ]; then
  RSYNC_ARGS+=(--delete)
fi

for skill in "${SKILLS[@]}"; do
  src="$RESTRICTED_DIR/$skill"
  dest="$OPENCLAW_SKILLS_DIR/$skill"

  if [ ! -d "$src" ]; then
    printf 'restricted skill not found: %s\n' "$src" >&2
    exit 1
  fi

  printf '==> %s\n' "$skill"
  mkdir -p "$dest"
  rsync "${RSYNC_ARGS[@]}" "$src/" "$dest/"
done
