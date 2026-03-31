#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

status_output="$("$BASE_DIR/browser-runtime.sh" status --run-dir "$TMP_DIR")"
printf '%s\n' "$status_output" | grep -q "status: stopped"

list_output="$("$BASE_DIR/browser-runtime.sh" list-targets --run-dir "$TMP_DIR")"
printf '%s\n' "$list_output" | grep -q '^\[\]$'

"$BASE_DIR/cleanup-host-runtime.sh" --run-dir "$TMP_DIR"
post_cleanup="$("$BASE_DIR/browser-runtime.sh" status --run-dir "$TMP_DIR")"
printf '%s\n' "$post_cleanup" | grep -q "status: closed"

mkdir -p "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/browser-stub" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
chmod +x "$TMP_DIR/bin/browser-stub"

start_output="$("$BASE_DIR/browser-runtime.sh" start \
  --run-dir "$TMP_DIR/task-run" \
  --profile-dir "$TMP_DIR/task-profile" \
  --url "https://example.com" \
  --origin "https://example.com" \
  --session-key default \
  --mode headless \
  --cdp-port 24555 \
  --browser "$TMP_DIR/bin/browser-stub")"
printf '%s\n' "$start_output" | grep -q "status: running"
printf '%s\n' "$start_output" | grep -q "profile_dir: $TMP_DIR/task-profile"

"$BASE_DIR/cleanup-host-runtime.sh" --run-dir "$TMP_DIR/task-run"
closed_output="$("$BASE_DIR/browser-runtime.sh" status --run-dir "$TMP_DIR/task-run" --origin "https://example.com" --session-key default)"
printf '%s\n' "$closed_output" | grep -q "status: closed"
