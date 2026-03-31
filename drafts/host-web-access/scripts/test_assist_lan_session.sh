#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/runtime-stub.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

command="${1:-}"
shift || true

case "$command" in
  status)
    cat <<OUT
status: running
mode: gui
url: https://example.com/protected
origin: https://example.com
session_key: default
run_dir: $TMP_DIR/runtime-run
profile_dir: $TMP_DIR/profile
cdp_host: 127.0.0.1
cdp_port: 9222
display: :88
browser_pid: 4242
browser_command: /usr/bin/google-chrome --remote-debugging-port=9222
OUT
    ;;
  *)
    echo "unexpected runtime command: $command" >&2
    exit 1
    ;;
esac
EOF
sed -i "s|\$TMP_DIR|$TMP_DIR|g" "$TMP_DIR/runtime-stub.sh"
chmod +x "$TMP_DIR/runtime-stub.sh"

cat >"$TMP_DIR/process-stub.sh" <<'EOF'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while :; do
  sleep 1
done
EOF
chmod +x "$TMP_DIR/process-stub.sh"

mkdir -p "$TMP_DIR/novnc-root"
run_root="$TMP_DIR/assist-run"
manifest_root="$TMP_DIR/manifests"
profile_dir="$TMP_DIR/profile"

set +e
bash "$BASE_DIR/assist-lan-session.sh" status --run-dir "$run_root" >/dev/null 2>&1
missing_status=$?
set -e
[ "$missing_status" -ne 0 ]

set +e
loopback_output="$(
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_X11VNC_BIN="$TMP_DIR/process-stub.sh" \
  AGENT_BROWSER_WEBSOCKIFY_BIN="$TMP_DIR/process-stub.sh" \
  AGENT_BROWSER_NOVNC_WEB_ROOT="$TMP_DIR/novnc-root" \
  AGENT_BROWSER_NOVNC_PUBLIC_HOST="127.0.0.1" \
    "$BASE_DIR/assist-lan-session.sh" start \
      --run-dir "$TMP_DIR/assist-loopback" \
      --origin "https://example.com" \
      --session-key default \
      --profile-dir "$profile_dir" \
      --manifest-root "$manifest_root" 2>&1
)"
loopback_status=$?
set -e
[ "$loopback_status" -ne 0 ]
printf '%s\n' "$loopback_output" | grep -q 'AGENT_BROWSER_NOVNC_PUBLIC_HOST'

AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
AGENT_BROWSER_X11VNC_BIN="$TMP_DIR/process-stub.sh" \
AGENT_BROWSER_WEBSOCKIFY_BIN="$TMP_DIR/process-stub.sh" \
AGENT_BROWSER_NOVNC_WEB_ROOT="$TMP_DIR/novnc-root" \
AGENT_BROWSER_NOVNC_PUBLIC_HOST="192.168.1.44" \
  "$BASE_DIR/assist-lan-session.sh" start \
    --run-dir "$run_root" \
    --origin "https://example.com" \
    --session-key default \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" >/dev/null

[ -f "$run_root/x11vnc.pid" ]
[ -f "$run_root/websockify.pid" ]
[ -f "$run_root/assist.env" ]

status="$("$BASE_DIR/assist-lan-session.sh" status --run-dir "$run_root")"
printf '%s\n' "$status" | grep -q '^lan_novnc_url: http://192\.168\.1\.44:6084/vnc\.html?autoconnect=1&resize=remote$'
printf '%s\n' "$status" | grep -vq '127.0.0.1'
printf '%s\n' "$status" | grep -vq '^novnc_url:'

"$BASE_DIR/assist-lan-session.sh" capture \
  --run-dir "$run_root" \
  --origin "https://example.com" \
  --session-key default \
  --profile-dir "$profile_dir" \
  --manifest-root "$manifest_root" >/dev/null

python3 - "$manifest_root" "$profile_dir" <<'PY'
import json
import sys
from pathlib import Path

manifest_root = Path(sys.argv[1])
profile_dir = sys.argv[2]
manifest_path = next(manifest_root.glob("sessions/**/*.json"))
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
assert manifest["state"] == "ready", manifest
assert manifest["profile_dir"] == profile_dir, manifest
assert manifest["novnc_port"] == 6084, manifest

registry_path = manifest_root / "index" / "site-sessions.json"
registry = json.loads(registry_path.read_text(encoding="utf-8"))
site = registry["sites"]["example.com"]
assert site["default_session"] == "default", site
assert site["sessions"]["default"]["profile_dir"] == profile_dir, site
PY

"$BASE_DIR/assist-lan-session.sh" stop --run-dir "$run_root" >/dev/null
[ ! -f "$run_root/x11vnc.pid" ]
[ ! -f "$run_root/websockify.pid" ]
[ ! -f "$run_root/assist.env" ]
