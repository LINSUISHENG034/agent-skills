#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/home/.agent-browser/profiles/x.com/Default"
touch "$TMP_DIR/home/.agent-browser/profiles/x.com/Default/Cookies"

"$BASE_DIR/site-session-registry.sh" write \
  --root "$TMP_DIR/home/.agent-browser" \
  --site "github.com" \
  --session-key default \
  --profile-dir "$TMP_DIR/home/.agent-browser/profiles/sites/github/default" \
  --source-origin "https://github.com" >/dev/null

registry_status="$(
  HOME="$TMP_DIR/home" \
  "$BASE_DIR/profile-resolution.sh" resolve \
    --root "$TMP_DIR/home/.agent-browser" \
    --origin "https://github.com" \
    --session-key default
)"
printf '%s\n' "$registry_status" | grep -q '"profile_dir": "'"$TMP_DIR"'/home/.agent-browser/profiles/sites/github/default"'
printf '%s\n' "$registry_status" | grep -q '"source": "site-registry"'

"$BASE_DIR/session-manifest.sh" write \
  --root "$TMP_DIR/manifests" \
  --origin "https://x.com" \
  --session-key default \
  --state ready \
  --browser-pid 123 \
  --profile-dir "$TMP_DIR/home/.agent-browser/profiles/x.com" >/dev/null

manifest_status="$(
  HOME="$TMP_DIR/home" \
  "$BASE_DIR/profile-resolution.sh" resolve \
    --root "$TMP_DIR/home/.agent-browser" \
    --manifest-root "$TMP_DIR/manifests" \
    --origin "https://x.com" \
    --session-key default
)"
printf '%s\n' "$manifest_status" | grep -q '"profile_dir": "'"$TMP_DIR"'/home/.agent-browser/profiles/x.com"'
printf '%s\n' "$manifest_status" | grep -q '"source": "manifest"'

legacy_status="$(
  HOME="$TMP_DIR/home" \
  "$BASE_DIR/profile-resolution.sh" resolve \
    --root "$TMP_DIR/home/.agent-browser" \
    --origin "https://x.com" \
    --session-key default
)"
printf '%s\n' "$legacy_status" | grep -q '"profile_dir": "'"$TMP_DIR"'/home/.agent-browser/profiles/x.com"'
printf '%s\n' "$legacy_status" | grep -q '"source": "legacy"'

mkdir -p "$TMP_DIR/home/.agent-browser/profiles/https___x_com/default/Default"
touch "$TMP_DIR/home/.agent-browser/profiles/https___x_com/default/Default/Login Data"
touch "$TMP_DIR/home/.agent-browser/profiles/https___x_com/default/Local State"
scoped_status="$(
  HOME="$TMP_DIR/home" \
  "$BASE_DIR/profile-resolution.sh" resolve \
    --root "$TMP_DIR/home/.agent-browser" \
    --origin "https://x.com" \
    --session-key default
)"
printf '%s\n' "$scoped_status" | grep -q '"profile_dir": "'"$TMP_DIR"'/home/.agent-browser/profiles/https___x_com/default"'
printf '%s\n' "$scoped_status" | grep -q '"source": "scoped"'

mkdir -p "$TMP_DIR/home/.agent-browser/index"
printf '{invalid json\n' >"$TMP_DIR/home/.agent-browser/index/identity-profiles.json"
write_output="$(
  HOME="$TMP_DIR/home" \
  "$BASE_DIR/profile-resolution.sh" write-identity \
    --root "$TMP_DIR/home/.agent-browser" \
    --provider "github.com" \
    --profile-dir "$TMP_DIR/home/.agent-browser/profiles/x.com" \
    --source-origin "https://x.com" \
    --source-session-key default
)"
[ -z "$write_output" ]
grep -q '"github.com"' "$TMP_DIR/home/.agent-browser/index/identity-profiles.json"
