#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/sync-restricted-skills.sh"

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

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

RESTRICTED_DIR="$TMPDIR/restricted"
OPENCLAW_SKILLS_DIR="$TMPDIR/openclaw-skills"

for skill in docx xlsx pdf pptx; do
  mkdir -p "$RESTRICTED_DIR/$skill/scripts" "$RESTRICTED_DIR/$skill/.venv" "$RESTRICTED_DIR/$skill/.pytest_cache"
  printf '%s\n' "$skill" > "$RESTRICTED_DIR/$skill/SKILL.md"
  printf 'script\n' > "$RESTRICTED_DIR/$skill/scripts/main.py"
  printf 'ignored\n' > "$RESTRICTED_DIR/$skill/.venv/ignored.txt"
  printf 'ignored\n' > "$RESTRICTED_DIR/$skill/.pytest_cache/ignored.txt"
done

mkdir -p "$OPENCLAW_SKILLS_DIR/docx"
printf 'stale\n' > "$OPENCLAW_SKILLS_DIR/docx/old.txt"

RESTRICTED_DIR="$RESTRICTED_DIR" OPENCLAW_SKILLS_DIR="$OPENCLAW_SKILLS_DIR" bash "$SCRIPT_PATH" >/dev/null

for skill in docx xlsx pdf pptx; do
  assert_file "$OPENCLAW_SKILLS_DIR/$skill/SKILL.md" "sync should copy skill manifest for $skill"
  assert_file "$OPENCLAW_SKILLS_DIR/$skill/scripts/main.py" "sync should copy scripts for $skill"
  assert_no_path "$OPENCLAW_SKILLS_DIR/$skill/.venv" "sync should exclude virtualenv for $skill"
  assert_no_path "$OPENCLAW_SKILLS_DIR/$skill/.pytest_cache" "sync should exclude pytest cache for $skill"
done

assert_no_path "$OPENCLAW_SKILLS_DIR/docx/old.txt" "sync should remove stale files from destination"
assert_eq "docx" "$(cat "$OPENCLAW_SKILLS_DIR/docx/SKILL.md")" "docx content should match source"
assert_eq "xlsx" "$(cat "$OPENCLAW_SKILLS_DIR/xlsx/SKILL.md")" "xlsx content should match source"

printf 'PASS: sync-restricted-skills\n'
