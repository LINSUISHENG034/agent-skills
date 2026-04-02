#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_REPO_ROOT="${SKILLS_REPO_ROOT:-$ROOT_DIR}"
OPENCLAW_SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-$HOME/.openclaw/skills}"
FROM_MODE="auto"
FROM_EXPLICIT=0
SOURCE_ROOT=""
DO_DELETE=1
SKILLS=()
RESOLVED_SRCS=()
RESOLVED_LABELS=()

usage() {
  cat <<'EOF'
Usage: scripts/sync-skill-to-openclaw.sh --skill <name> [--skill <name> ...]
       [--from auto|root|drafts|restricted]
       [--source-root <abs-path>]
       [--no-delete]

Sync one or more skills into the OpenClaw local skills directory.

Options:
  --skill <name>                      Sync the named skill. Repeat to sync multiple skills.
  --from auto|root|drafts|restricted Resolve skills from the repository root, drafts,
                                     restricted, or auto-detect across all three.
                                     Default: auto
  --source-root <abs-path>           Resolve skills from an explicit absolute source root.
  --no-delete                        Keep destination-only files instead of removing them.
  -h, --help

Environment:
  SKILLS_REPO_ROOT      Repository root used for --from root|drafts|restricted
                        and --from auto. Default: the current repository root
  OPENCLAW_SKILLS_DIR  Target directory. Default: ~/.openclaw/skills
EOF
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

repo_root_for_mode() {
  case "$1" in
    root)
      printf '%s\n' "$SKILLS_REPO_ROOT"
      ;;
    drafts)
      printf '%s\n' "$SKILLS_REPO_ROOT/drafts"
      ;;
    restricted)
      printf '%s\n' "$SKILLS_REPO_ROOT/restricted"
      ;;
    *)
      fail "Unknown --from value: $1"
      ;;
  esac
}

validate_skill_in_root() {
  local base_root="$1"
  local skill="$2"
  local manifest="$base_root/$skill/SKILL.md"

  if [ ! -f "$manifest" ]; then
    fail "skill '$skill' not found or missing SKILL.md under: $base_root/$skill"
  fi

  printf '%s\n' "$base_root/$skill"
}

resolve_auto_skill() {
  local skill="$1"
  local base_root=""
  local candidate=""
  local matches=()
  local labels=()
  local search_modes=(root drafts restricted)
  local match_summary=""
  local i=0

  for base_label in "${search_modes[@]}"; do
    base_root="$(repo_root_for_mode "$base_label")"
    candidate="$base_root/$skill/SKILL.md"
    if [ -f "$candidate" ]; then
      matches+=("$base_root/$skill")
      labels+=("$base_label/$skill")
    fi
  done

  if [ "${#matches[@]}" -eq 0 ]; then
    fail "skill '$skill' was not found in root, drafts, or restricted"
  fi

  if [ "${#matches[@]}" -gt 1 ]; then
    match_summary="${labels[0]}"
    for ((i = 1; i < ${#labels[@]}; i++)); do
      match_summary="$match_summary, ${labels[i]}"
    done
    fail "multiple matches found for skill '$skill': $match_summary. Re-run with --from."
  fi

  RESOLVED_SRCS+=("${matches[0]}")
  RESOLVED_LABELS+=("${labels[0]}")
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skill)
      [ "$#" -ge 2 ] || {
        usage >&2
        fail "Missing value for --skill"
      }
      SKILLS+=("$2")
      shift
      ;;
    --from)
      [ "$#" -ge 2 ] || {
        usage >&2
        fail "Missing value for --from"
      }
      FROM_MODE="$2"
      FROM_EXPLICIT=1
      shift
      ;;
    --source-root)
      [ "$#" -ge 2 ] || {
        usage >&2
        fail "Missing value for --source-root"
      }
      SOURCE_ROOT="$2"
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
      usage >&2
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

if [ "${#SKILLS[@]}" -eq 0 ]; then
  usage >&2
  fail "At least one --skill is required"
fi

if [ -n "$SOURCE_ROOT" ] && [ "$FROM_EXPLICIT" -eq 1 ]; then
  fail "--source-root cannot be combined with --from"
fi

if [ -n "$SOURCE_ROOT" ] && [[ "$SOURCE_ROOT" != /* ]]; then
  fail "--source-root must be an absolute path"
fi

if ! command -v rsync >/dev/null 2>&1; then
  fail "rsync is required but was not found in PATH"
fi

if [ -n "$SOURCE_ROOT" ] && [ ! -d "$SOURCE_ROOT" ]; then
  fail "source root directory not found: $SOURCE_ROOT"
fi

if [ ! -d "$SKILLS_REPO_ROOT" ]; then
  fail "skills repository root not found: $SKILLS_REPO_ROOT"
fi

if [ -z "$SOURCE_ROOT" ] && [ "$FROM_MODE" != "auto" ]; then
  REPO_SOURCE_ROOT="$(repo_root_for_mode "$FROM_MODE")"
  if [ ! -d "$REPO_SOURCE_ROOT" ]; then
    fail "source directory not found: $REPO_SOURCE_ROOT"
  fi
fi

for skill in "${SKILLS[@]}"; do
  if [ -n "$SOURCE_ROOT" ]; then
    RESOLVED_SRCS+=("$(validate_skill_in_root "$SOURCE_ROOT" "$skill")")
    RESOLVED_LABELS+=("source-root/$skill")
  elif [ "$FROM_MODE" = "auto" ]; then
    resolve_auto_skill "$skill"
  else
    RESOLVED_SRCS+=("$(validate_skill_in_root "$REPO_SOURCE_ROOT" "$skill")")
    RESOLVED_LABELS+=("$FROM_MODE/$skill")
  fi
done

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

for i in "${!SKILLS[@]}"; do
  skill="${SKILLS[$i]}"
  src="${RESOLVED_SRCS[$i]}"
  label="${RESOLVED_LABELS[$i]}"
  dest="$OPENCLAW_SKILLS_DIR/$skill"

  printf '==> %s (%s)\n' "$skill" "$label"
  mkdir -p "$dest"
  rsync "${RSYNC_ARGS[@]}" "$src/" "$dest/"
done
