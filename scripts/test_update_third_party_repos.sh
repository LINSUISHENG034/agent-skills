#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/update-third-party-repos.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    printf 'ASSERTION FAILED: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_ne() {
  local left="$1"
  local right="$2"
  local message="$3"

  if [ "$left" = "$right" ]; then
    printf 'ASSERTION FAILED: %s\nboth: %s\n' "$message" "$left" >&2
    exit 1
  fi
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ORIGIN_REPO="$TMPDIR/origin.git"
SEED_REPO="$TMPDIR/seed"
ADVANCE_REPO="$TMPDIR/advance"
REPOS_DIR="$TMPDIR/third_party/repos"
SAMPLE_REPO="$REPOS_DIR/sample"

mkdir -p "$REPOS_DIR"
git init --bare --initial-branch=main "$ORIGIN_REPO" >/dev/null
git clone "$ORIGIN_REPO" "$SEED_REPO" >/dev/null 2>&1

git -C "$SEED_REPO" config user.name "Codex Test"
git -C "$SEED_REPO" config user.email "codex@example.com"
printf 'v1\n' > "$SEED_REPO/file.txt"
git -C "$SEED_REPO" add file.txt
git -C "$SEED_REPO" commit -m "initial" >/dev/null
git -C "$SEED_REPO" push origin main >/dev/null 2>&1

git clone "$ORIGIN_REPO" "$SAMPLE_REPO" >/dev/null 2>&1

git clone "$ORIGIN_REPO" "$ADVANCE_REPO" >/dev/null 2>&1
git -C "$ADVANCE_REPO" config user.name "Codex Test"
git -C "$ADVANCE_REPO" config user.email "codex@example.com"
printf 'v2\n' > "$ADVANCE_REPO/file.txt"
git -C "$ADVANCE_REPO" add file.txt
git -C "$ADVANCE_REPO" commit -m "advance" >/dev/null
git -C "$ADVANCE_REPO" push origin main >/dev/null 2>&1

initial_head="$(git -C "$SAMPLE_REPO" rev-parse HEAD)"
advanced_head="$(git -C "$ADVANCE_REPO" rev-parse HEAD)"

THIRD_PARTY_REPOS_DIR="$REPOS_DIR" "$SCRIPT_PATH" >/dev/null

fetched_remote_head="$(git -C "$SAMPLE_REPO" rev-parse origin/main)"
head_after_fetch="$(git -C "$SAMPLE_REPO" rev-parse HEAD)"

assert_eq "$advanced_head" "$fetched_remote_head" "fetch-only mode should update the remote tracking branch"
assert_eq "$initial_head" "$head_after_fetch" "fetch-only mode should not move the local checkout"
assert_ne "$advanced_head" "$head_after_fetch" "fetch-only mode must leave the local checkout behind the remote"

THIRD_PARTY_REPOS_DIR="$REPOS_DIR" "$SCRIPT_PATH" --pull >/dev/null

head_after_pull="$(git -C "$SAMPLE_REPO" rev-parse HEAD)"
assert_eq "$advanced_head" "$head_after_pull" "--pull should fast-forward the local checkout"

printf 'PASS: update-third-party-repos\n'
