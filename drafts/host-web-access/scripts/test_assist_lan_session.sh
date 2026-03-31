#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_root="$TMP_DIR/run"
profile_dir="$TMP_DIR/profile"

set +e
bash "$BASE_DIR/assist-lan-session.sh" status --run-dir "$run_root" >/dev/null 2>&1
EXIT_STATUS=$?
set -e
[ "$EXIT_STATUS" -ne 0 ]

"$BASE_DIR/assist-lan-session.sh" start --run-dir "$run_root" --origin "https://example.com" --session-key default --profile-dir "$profile_dir"
status="$("$BASE_DIR/assist-lan-session.sh" status --run-dir "$run_root")"
printf '%s\n' "$status" | grep -q 'lan_novnc_url:'
printf '%s\n' "$status" | grep -vq '127.0.0.1'
capture_dir="$TMP_DIR/manifests"
"$BASE_DIR/assist-lan-session.sh" capture --run-dir "$run_root" --origin "https://example.com" --session-key default --profile-dir "$profile_dir" --manifest-root "$capture_dir"
manifest_path="$(find "$capture_dir" -type f -name '*.json' | head -n 1)"
[ -s "$manifest_path" ]
"$BASE_DIR/assist-lan-session.sh" stop --run-dir "$run_root"
[ ! -f "$run_root/state.env" ]
