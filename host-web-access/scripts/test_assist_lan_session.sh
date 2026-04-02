#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/home"
export HOME="$TMP_DIR/home"

assert_json_value() {
  local payload="$1"
  local field="$2"
  local expected="$3"
  python3 - "$payload" "$field" "$expected" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
field = sys.argv[2]
expected = sys.argv[3]
actual = data.get(field)
if isinstance(actual, bool):
    actual = "true" if actual else "false"
assert actual == expected, data
PY
}

assert_json_has_fields() {
  local payload="$1"
  shift
  python3 - "$payload" "$@" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
for field in sys.argv[2:]:
    assert field in data, data
PY
}

cat >"$TMP_DIR/runtime-stub.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

TARGETS_JSON="${RUNTIME_STUB_TARGETS_JSON:-}"
PAGE_URL="${RUNTIME_STUB_PAGE_URL:-https://example.com/protected}"
PAGE_TITLE="${RUNTIME_STUB_PAGE_TITLE:-Example}"
PAGE_BODY="${RUNTIME_STUB_PAGE_BODY:-hello}"
PAGE_CHALLENGE="${RUNTIME_STUB_PAGE_CHALLENGE:-false}"
PAGE_LOGIN_WALL="${RUNTIME_STUB_PAGE_LOGIN_WALL:-false}"
if [ -z "$TARGETS_JSON" ]; then
  TARGETS_JSON='[{"id":"page-1","type":"page","url":"https://example.com/protected"}]'
fi
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
  list-targets)
    printf '%s\n' "$TARGETS_JSON"
    ;;
  select-target)
    python3 - "$TARGETS_JSON" "$@" <<'PY'
import json
import sys
from urllib.parse import urlparse

targets_json = sys.argv[1]
args = sys.argv[2:]
origin = ""
target_url = ""
while args:
    key = args.pop(0)
    if key == "--origin":
        origin = args.pop(0)
    elif key == "--target-url":
        target_url = args.pop(0)
    elif key == "--targets-json":
        targets_json = args.pop(0)

targets = [target for target in json.loads(targets_json) if target.get("type") == "page"]

def host(value):
    parsed = urlparse(value)
    return parsed.netloc

def score(target):
    url = target.get("url", "")
    if target_url and url == target_url:
        return (0, url)
    if origin and url.startswith(origin):
        return (1, url)
    if origin and host(url) and host(url) == host(origin):
        return (2, url)
    return (9, url)

if targets:
    print(sorted(targets, key=score)[0].get("id", ""))
PY
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
        if [ "$PAGE_CHALLENGE" = "true" ]; then
          echo '{"hasChallenge": true, "indicators": ["turnstile"]}'
        else
          echo '{"hasChallenge": false, "indicators": []}'
        fi
        ;;
      login-wall)
        if [ "$PAGE_LOGIN_WALL" = "true" ]; then
          echo '{"hasLoginWall": true, "loginHits": ["Sign in"]}'
        else
          echo '{"hasLoginWall": false, "loginHits": []}'
        fi
        ;;
      page-info)
        printf '{"title":"%s","url":"%s","bodySnippet":"%s"}\n' "$PAGE_TITLE" "$PAGE_URL" "$PAGE_BODY"
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

cat >"$TMP_DIR/websockify-fail-stub.sh" <<'EOF'
#!/usr/bin/env bash
echo "simulated websockify start failure" >&2
exit 1
EOF
chmod +x "$TMP_DIR/websockify-fail-stub.sh"

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
  AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
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

set +e
partial_start_output="$(
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_X11VNC_BIN="$TMP_DIR/process-stub.sh" \
  AGENT_BROWSER_WEBSOCKIFY_BIN="$TMP_DIR/websockify-fail-stub.sh" \
  AGENT_BROWSER_NOVNC_WEB_ROOT="$TMP_DIR/novnc-root" \
  AGENT_BROWSER_NOVNC_PUBLIC_HOST="192.168.1.44" \
    "$BASE_DIR/assist-lan-session.sh" start \
      --run-dir "$TMP_DIR/assist-partial-fail" \
      --origin "https://example.com" \
      --session-key default \
      --profile-dir "$profile_dir" \
      --manifest-root "$manifest_root" 2>&1
)"
partial_start_status=$?
set -e
[ "$partial_start_status" -ne 0 ]
printf '%s\n' "$partial_start_output" | grep -q 'websockify'
[ ! -f "$TMP_DIR/assist-partial-fail/x11vnc.pid" ]
[ ! -f "$TMP_DIR/assist-partial-fail/websockify.pid" ]
[ ! -f "$TMP_DIR/assist-partial-fail/assist.env" ]
! pgrep -f "$TMP_DIR/process-stub.sh" >/dev/null 2>&1

start_output="$(
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_X11VNC_BIN="$TMP_DIR/process-stub.sh" \
  AGENT_BROWSER_WEBSOCKIFY_BIN="$TMP_DIR/process-stub.sh" \
  AGENT_BROWSER_NOVNC_WEB_ROOT="$TMP_DIR/novnc-root" \
  AGENT_BROWSER_NOVNC_PUBLIC_HOST="192.168.1.44" \
    "$BASE_DIR/assist-lan-session.sh" start \
      --run-dir "$run_root" \
      --origin "https://example.com" \
      --session-key default \
      --profile-dir "$profile_dir" \
      --manifest-root "$manifest_root"
)"

assert_json_has_fields "$start_output" status next_action operator_required operator_url lan_novnc_url resume_command message_for_agent
assert_json_value "$start_output" status needs-user
assert_json_value "$start_output" next_action open-novnc
assert_json_value "$start_output" operator_required true
assert_json_value "$start_output" operator_url "http://192.168.1.44:6084/vnc.html?autoconnect=1&resize=remote"
assert_json_value "$start_output" lan_novnc_url "http://192.168.1.44:6084/vnc.html?autoconnect=1&resize=remote"

[ -f "$run_root/x11vnc.pid" ]
[ -f "$run_root/websockify.pid" ]
[ -f "$run_root/assist.env" ]

status="$("$BASE_DIR/assist-lan-session.sh" status --run-dir "$run_root")"
assert_json_has_fields "$status" status next_action operator_required operator_url lan_novnc_url resume_command message_for_agent
assert_json_value "$status" status needs-user
assert_json_value "$status" next_action open-novnc
assert_json_value "$status" operator_required true
assert_json_value "$status" operator_url "http://192.168.1.44:6084/vnc.html?autoconnect=1&resize=remote"
assert_json_value "$status" lan_novnc_url "http://192.168.1.44:6084/vnc.html?autoconnect=1&resize=remote"

set +e
challenge_output="$(
  RUNTIME_STUB_PAGE_CHALLENGE=true \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assist-lan-session.sh" capture \
    --run-dir "$run_root" \
    --origin "https://example.com" \
    --session-key default \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" 2>&1
)"
challenge_status=$?
set -e
[ "$challenge_status" -ne 0 ]
printf '%s\n' "$challenge_output" | grep -q 'challenge'
test ! -d "$manifest_root/sessions"

set +e
login_output="$(
  RUNTIME_STUB_PAGE_LOGIN_WALL=true \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assist-lan-session.sh" capture \
    --run-dir "$run_root" \
    --origin "https://example.com" \
    --session-key default \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" 2>&1
)"
login_status=$?
set -e
[ "$login_status" -ne 0 ]
printf '%s\n' "$login_output" | grep -q 'login wall'
test ! -d "$manifest_root/sessions"
test ! -f "$HOME/.agent-browser/index/site-sessions.json"
test ! -f "$HOME/.agent-browser/index/identity-profiles.json"

set +e
off_origin_output="$(
  RUNTIME_STUB_PAGE_URL='https://news.ycombinator.com/' \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assist-lan-session.sh" capture \
    --run-dir "$run_root" \
    --origin "https://example.com" \
    --session-key default \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" 2>&1
)"
off_origin_status=$?
set -e
[ "$off_origin_status" -ne 0 ]
printf '%s\n' "$off_origin_output" | grep -q 'requested'
test ! -d "$manifest_root/sessions"

set +e
wrong_target_output="$(
  RUNTIME_STUB_PAGE_URL='https://example.com/settings' \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assist-lan-session.sh" capture \
    --run-dir "$run_root" \
    --origin "https://example.com" \
    --target-url "https://example.com/protected" \
    --session-key default \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" 2>&1
)"
wrong_target_status=$?
set -e
[ "$wrong_target_status" -ne 0 ]
printf '%s\n' "$wrong_target_output" | grep -q 'requested target page'
test ! -d "$manifest_root/sessions"

capture_output="$(
  RUNTIME_STUB_PAGE_URL='https://example.com/protected/' \
  RUNTIME_STUB_PAGE_TITLE='Example Protected' \
  RUNTIME_STUB_PAGE_BODY='ready' \
  RUNTIME_STUB_TARGETS_JSON='[
    {"id":"page-example","type":"page","url":"https://example.com/protected"}
  ]' \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  AGENT_BROWSER_SELECT_TARGET_HELPER="$TMP_DIR/runtime-stub.sh" \
    "$BASE_DIR/assist-lan-session.sh" capture \
      --run-dir "$run_root" \
      --origin "https://example.com" \
      --target-url "https://example.com/protected" \
      --session-key default \
      --profile-dir "$profile_dir" \
      --manifest-root "$manifest_root"
)"

assert_json_has_fields "$capture_output" status next_action operator_required operator_url lan_novnc_url capture_completed
assert_json_value "$capture_output" status ready
assert_json_value "$capture_output" next_action none
assert_json_value "$capture_output" operator_required false
assert_json_value "$capture_output" capture_completed true
assert_json_value "$capture_output" operator_url "http://192.168.1.44:6084/vnc.html?autoconnect=1&resize=remote"

python3 - "$manifest_root" "$profile_dir" "$HOME/.agent-browser" <<'PY'
import json
import sys
from pathlib import Path

manifest_root = Path(sys.argv[1])
profile_dir = sys.argv[2]
base_root = Path(sys.argv[3])
manifest_path = next(manifest_root.glob("sessions/**/*.json"))
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
assert manifest["state"] == "ready", manifest
assert manifest["profile_dir"] == profile_dir, manifest
assert manifest["novnc_port"] == 6084, manifest

registry_path = base_root / "index" / "site-sessions.json"
registry = json.loads(registry_path.read_text(encoding="utf-8"))
site = registry["sites"]["example.com"]
assert site["default_session"] == "default", site
assert site["sessions"]["default"]["profile_dir"] == profile_dir, site

identity_path = base_root / "index" / "identity-profiles.json"
identity = json.loads(identity_path.read_text(encoding="utf-8"))
assert "example.com" in identity["providers"], identity
assert identity["providers"]["example.com"]["profile_dir"] == profile_dir, identity

assert not (manifest_root / "index" / "identity-profiles.json").exists()
PY

stop_output="$("$BASE_DIR/assist-lan-session.sh" stop --run-dir "$run_root")"
assert_json_has_fields "$stop_output" status next_action operator_required assisted_session_stopped
assert_json_value "$stop_output" status stopped
assert_json_value "$stop_output" next_action none
assert_json_value "$stop_output" operator_required false
assert_json_value "$stop_output" assisted_session_stopped true
[ ! -f "$run_root/x11vnc.pid" ]
[ ! -f "$run_root/websockify.pid" ]
[ ! -f "$run_root/assist.env" ]
