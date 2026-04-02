#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/sync-skill-to-openclaw.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    printf 'ASSERTION FAILED: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_file() {
  local path="$1"
  local message="$2"

  if [ ! -f "$path" ]; then
    printf 'ASSERTION FAILED: %s\nmissing file: %s\n' "$message" "$path" >&2
    exit 1
  fi
}

assert_no_path() {
  local path="$1"
  local message="$2"

  if [ -e "$path" ]; then
    printf 'ASSERTION FAILED: %s\nunexpected path: %s\n' "$message" "$path" >&2
    exit 1
  fi
}

assert_contains() {
  local path="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -Fq "$pattern" "$path"; then
    printf 'ASSERTION FAILED: %s\nmissing pattern: %s\nin file: %s\n' "$message" "$pattern" "$path" >&2
    exit 1
  fi
}

run_success() {
  local log_path="$1"
  shift

  if ! "$@" >"$log_path" 2>&1; then
    printf 'COMMAND FAILED UNEXPECTEDLY:\n%s\n' "$*" >&2
    cat "$log_path" >&2
    exit 1
  fi
}

run_failure() {
  local log_path="$1"
  shift

  if "$@" >"$log_path" 2>&1; then
    printf 'COMMAND SUCCEEDED UNEXPECTEDLY:\n%s\n' "$*" >&2
    cat "$log_path" >&2
    exit 1
  fi
}

make_skill() {
  local root="$1"
  local skill="$2"

  mkdir -p "$root/$skill/scripts" "$root/$skill/.venv" "$root/$skill/.pytest_cache"
  printf '%s\n' "$skill" > "$root/$skill/SKILL.md"
  printf 'script\n' > "$root/$skill/scripts/main.py"
  printf 'ignored\n' > "$root/$skill/.venv/ignored.txt"
  printf 'ignored\n' > "$root/$skill/.pytest_cache/ignored.txt"
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ROOT_REPO="$TMPDIR/repo"
OPENCLAW_SKILLS_DIR="$TMPDIR/openclaw-skills"
LOG_PATH="$TMPDIR/test.log"

mkdir -p "$ROOT_REPO/drafts" "$ROOT_REPO/restricted"

make_skill "$ROOT_REPO/restricted" "docx"
make_skill "$ROOT_REPO/restricted" "xlsx"
make_skill "$ROOT_REPO" "root-only"
make_skill "$ROOT_REPO/drafts" "draft-only"
make_skill "$ROOT_REPO/restricted" "restricted-only"
make_skill "$ROOT_REPO" "shared-skill"
make_skill "$ROOT_REPO/drafts" "shared-skill"

mkdir -p "$ROOT_REPO/restricted/no-manifest/scripts"
printf 'script\n' > "$ROOT_REPO/restricted/no-manifest/scripts/main.py"

mkdir -p "$OPENCLAW_SKILLS_DIR/docx"
printf 'stale\n' > "$OPENCLAW_SKILLS_DIR/docx/old.txt"

run_success "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" \
  bash "$SCRIPT_PATH" --from restricted --skill docx --skill xlsx

for skill in docx xlsx; do
  assert_file "$OPENCLAW_SKILLS_DIR/$skill/SKILL.md" "sync should copy skill manifest for $skill"
  assert_file "$OPENCLAW_SKILLS_DIR/$skill/scripts/main.py" "sync should copy scripts for $skill"
  assert_no_path "$OPENCLAW_SKILLS_DIR/$skill/.venv" "sync should exclude virtualenv for $skill"
  assert_no_path "$OPENCLAW_SKILLS_DIR/$skill/.pytest_cache" "sync should exclude pytest cache for $skill"
done

assert_no_path "$OPENCLAW_SKILLS_DIR/docx/old.txt" "sync should remove stale files from destination"
assert_eq "docx" "$(cat "$OPENCLAW_SKILLS_DIR/docx/SKILL.md")" "docx content should match source"
assert_eq "xlsx" "$(cat "$OPENCLAW_SKILLS_DIR/xlsx/SKILL.md")" "xlsx content should match source"

run_success "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" \
  bash "$SCRIPT_PATH" --from root --skill root-only
assert_file "$OPENCLAW_SKILLS_DIR/root-only/SKILL.md" "root source should sync root-level skill"

run_success "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" \
  bash "$SCRIPT_PATH" --from drafts --skill draft-only
assert_file "$OPENCLAW_SKILLS_DIR/draft-only/SKILL.md" "draft source should sync draft skill"

run_success "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" \
  bash "$SCRIPT_PATH" --skill restricted-only
assert_file "$OPENCLAW_SKILLS_DIR/restricted-only/SKILL.md" "auto mode should sync a uniquely matched restricted skill"

run_failure "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" \
  bash "$SCRIPT_PATH" --skill shared-skill
assert_contains "$LOG_PATH" "multiple matches found for skill" "auto mode should fail on ambiguous skills"

EXTERNAL_ROOT="$TMPDIR/external-skills"
mkdir -p "$EXTERNAL_ROOT"
make_skill "$EXTERNAL_ROOT" "external-only"

run_success "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" \
  bash "$SCRIPT_PATH" --source-root "$EXTERNAL_ROOT" --skill external-only
assert_file "$OPENCLAW_SKILLS_DIR/external-only/SKILL.md" "absolute source-root should sync external skill"

run_failure "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" \
  bash "$SCRIPT_PATH" --source-root relative/path --skill external-only
assert_contains "$LOG_PATH" "absolute path" "relative source-root should fail"

run_failure "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" \
  bash "$SCRIPT_PATH" --from restricted --skill no-manifest
assert_contains "$LOG_PATH" "SKILL.md" "missing manifest should fail"

PRECHECK_DEST="$TMPDIR/precheck-dest"
run_failure "$LOG_PATH" env \
  SKILLS_REPO_ROOT="$ROOT_REPO" \
  OPENCLAW_SKILLS_DIR="$PRECHECK_DEST" \
  bash "$SCRIPT_PATH" --from restricted --skill docx --skill missing-skill
assert_no_path "$PRECHECK_DEST/docx" "failed preflight should prevent syncing earlier valid skills"

printf 'PASS: sync-skill-to-openclaw\n'
