#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/home"
export HOME="$TMP_DIR/home"

cat >"$TMP_DIR/runtime-stub.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

TARGETS_JSON="${RUNTIME_STUB_TARGETS_JSON:-}"
PAGE_URL="${RUNTIME_STUB_PAGE_URL:-https://github.com/settings/profile}"
if [ -z "$TARGETS_JSON" ]; then
  TARGETS_JSON='[{"id":"page-1","type":"page","url":"https://github.com/settings/profile"}]'
fi
command="${1:-}"
shift || true

case "$command" in
  status)
    cat <<OUT
status: running
mode: gui
url: $PAGE_URL
origin: https://github.com
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
  list-targets)
    printf '%s\n' "$TARGETS_JSON"
    ;;
  select-target)
    echo "page-1"
    ;;
  check-page)
    check=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --check)
          check="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    case "$check" in
      challenge)
        echo '{"hasChallenge": false, "indicators": []}'
        ;;
      login-wall)
        echo '{"hasLoginWall": false, "loginHits": []}'
        ;;
      page-info)
        printf '{"title":"GitHub Settings","url":"%s","bodySnippet":"settings"}\n' "$PAGE_URL"
        ;;
      *)
        echo '{}'
        ;;
    esac
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
manifest_root="$TMP_DIR/override-manifests"
profile_dir="$TMP_DIR/profile"

AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
AGENT_BROWSER_X11VNC_BIN="$TMP_DIR/process-stub.sh" \
AGENT_BROWSER_WEBSOCKIFY_BIN="$TMP_DIR/process-stub.sh" \
AGENT_BROWSER_NOVNC_WEB_ROOT="$TMP_DIR/novnc-root" \
AGENT_BROWSER_NOVNC_PUBLIC_HOST="192.168.1.44" \
  "$BASE_DIR/assist-lan-session.sh" start \
    --run-dir "$run_root" \
    --origin "https://github.com" \
    --target-url "https://github.com/settings/profile" \
    --session-key default \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" >/dev/null

AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assist-lan-session.sh" capture \
    --run-dir "$run_root" \
    --origin "https://github.com" \
    --target-url "https://github.com/settings/profile" \
    --session-key default \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" >/dev/null

python3 - "$HOME/.agent-browser" "$manifest_root" "$profile_dir" <<'PY'
import json
import sys
from pathlib import Path

base_root = Path(sys.argv[1])
manifest_root = Path(sys.argv[2])
profile_dir = sys.argv[3]

identity_path = base_root / "index" / "identity-profiles.json"
assert identity_path.exists(), identity_path
identity = json.loads(identity_path.read_text(encoding="utf-8"))
entry = identity["providers"]["github.com"]
assert entry["profile_dir"] == profile_dir, entry
assert entry["source_origin"] == "https://github.com", entry
assert entry["source_session_key"] == "default", entry

assert not (manifest_root / "index" / "identity-profiles.json").exists()
PY

rm -f "$HOME/.agent-browser/index/site-sessions.json"

resolved="$(
  "$BASE_DIR/profile-resolution.sh" resolve \
    --root "$HOME/.agent-browser" \
    --manifest-root "$TMP_DIR/blank-manifests" \
    --origin "https://github.com" \
    --session-key default
)"
printf '%s\n' "$resolved" | grep -q '"source": "identity-index"'
printf '%s\n' "$resolved" | grep -q '"provider": "github.com"'
printf '%s\n' "$resolved" | grep -q '"profile_dir": "'"$profile_dir"'"'

"$BASE_DIR/assist-lan-session.sh" stop --run-dir "$run_root" >/dev/null
