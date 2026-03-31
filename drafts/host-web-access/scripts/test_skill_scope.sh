#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DOC="$ROOT_DIR/SKILL.md"
IDENTITY_POLICY_DOC="$ROOT_DIR/references/identity-session-policy.md"
USE_CASES_DOC="$ROOT_DIR/references/use-cases.md"
TEST_MATRIX_DOC="$ROOT_DIR/references/testing-matrix.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! rg -q "$pattern" "$file"; then
    fail "$label (missing in $file)"
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if rg -q "$pattern" "$file"; then
    fail "$label (found in $file)"
  fi
}

assert_contains "$SKILL_DOC" "canonical normal entrypoint" "canonical normal entrypoint rule"
assert_contains "$IDENTITY_POLICY_DOC" "one primary identity per canonical site" "primary identity default rule"
assert_contains "$IDENTITY_POLICY_DOC" "No automatic guessing between multiple identities" "no identity guessing rule"
assert_contains "$IDENTITY_POLICY_DOC" "non-default identities require an explicit session-key" "explicit session-key requirement"
assert_contains "$SKILL_DOC" "host-browser workflow by default" "protected-site browser-route discipline"
assert_contains "$SKILL_DOC" "Assisted flow is the exception path" "assisted flow exception rule"
assert_contains "$USE_CASES_DOC" "wrong-page recovery before user takeover" "wrong-page recovery use case coverage"
assert_contains "$TEST_MATRIX_DOC" "identity governance" "identity governance matrix coverage"
assert_contains "$TEST_MATRIX_DOC" "LAN-only assisted handoff" "LAN-only assisted handoff matrix coverage"
assert_contains "$TEST_MATRIX_DOC" "browser-route continuity on protected tasks" "protected-task route continuity matrix coverage"

assert_not_contains "$SKILL_DOC" "\\bnovnc_url\\b" "public docs should not expose generic novnc_url"
assert_not_contains "$SKILL_DOC" "loopback" "public docs should not mention loopback handoff"
assert_not_contains "$IDENTITY_POLICY_DOC" "\\bnovnc_url\\b" "identity policy should not expose generic novnc_url"
assert_not_contains "$IDENTITY_POLICY_DOC" "loopback" "identity policy should not mention loopback handoff"
assert_not_contains "$USE_CASES_DOC" "\\bnovnc_url\\b" "use cases should not expose generic novnc_url"
assert_not_contains "$USE_CASES_DOC" "loopback" "use cases should not mention loopback handoff"
assert_not_contains "$TEST_MATRIX_DOC" "\\bnovnc_url\\b" "testing matrix should not expose generic novnc_url"
assert_not_contains "$TEST_MATRIX_DOC" "loopback" "testing matrix should not mention loopback handoff"

echo "PASS: scope contract checks passed"
