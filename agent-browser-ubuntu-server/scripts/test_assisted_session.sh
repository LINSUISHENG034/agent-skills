#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/runtime-stub.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${RUNTIME_STUB_DIR:?}"
TARGETS_JSON="${RUNTIME_STUB_TARGETS_JSON:-}"
if [ -z "$TARGETS_JSON" ]; then
  TARGETS_JSON='[{"id":"page-1","type":"page","url":"https://example.com"}]'
fi
command="${1:-}"
shift || true

case "$command" in
  start)
    touch "$STATE_DIR/running"
    cat <<OUT
runtime: running
mode: gui
url: https://example.com
profile_dir: $STATE_DIR/profile
run_dir: $STATE_DIR/run
cdp_port: 19222
browser_pid: $$
xvfb_pid: 4242
display: :88
OUT
    ;;
  status)
    if [ -f "$STATE_DIR/running" ]; then
      cat <<OUT
runtime: running
mode: gui
url: https://example.com
profile_dir: $STATE_DIR/profile
run_dir: $STATE_DIR/run
cdp_port: 19222
browser_pid: $$
xvfb_pid: 4242
display: :88
OUT
    else
      cat <<OUT
runtime: stopped
mode: gui
url: https://example.com
profile_dir: $STATE_DIR/profile
run_dir: $STATE_DIR/run
cdp_port: 19222
browser_pid:
xvfb_pid:
display: :88
OUT
    fi
    ;;
  list-targets)
    if [ -f "$STATE_DIR/running" ]; then
      printf '%s\n' "$TARGETS_JSON"
    else
      echo '[]'
    fi
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
    if [ ! -f "$STATE_DIR/verified" ]; then
      if [ "$check" = "challenge" ]; then
        echo '{"hasChallenge": true, "indicators": ["turnstile"], "title": "Verify you are human", "url": "https://example.com"}'
      elif [ "$check" = "login-wall" ]; then
        echo '{"hasLoginWall": true, "loginHits": ["Sign in"], "title": "Sign in", "url": "https://example.com/login"}'
      else
        echo '{"title": "Verify you are human", "url": "https://example.com", "bodySnippet": "challenge"}'
      fi
    else
      if [ "$check" = "challenge" ]; then
        echo '{"hasChallenge": false, "indicators": [], "title": "Dashboard", "url": "https://example.com"}'
      elif [ "$check" = "login-wall" ]; then
        echo '{"hasLoginWall": false, "loginHits": [], "title": "Dashboard", "url": "https://example.com"}'
      else
        echo '{"title": "Dashboard", "url": "https://example.com", "bodySnippet": "hello"}'
      fi
    fi
    ;;
  stop)
    rm -f "$STATE_DIR/running" "$STATE_DIR/verified"
    ;;
  *)
    echo "unknown command: $command" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$TMP_DIR/runtime-stub.sh"

RUNTIME_STUB_DIR="$TMP_DIR/runtime" AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assisted-session.sh" status --run-dir "$TMP_DIR" >/dev/null

mkdir -p "$TMP_DIR/home"
assist_status="$(
  HOME="$TMP_DIR/home" \
  RUNTIME_STUB_DIR="$TMP_DIR/runtime" \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assisted-session.sh" status \
    --url "https://foxcode.rjj.cc/api-keys" \
    --origin "https://foxcode.rjj.cc" \
    --session-key "foxcode-main"
)"
printf '%s\n' "$assist_status" | grep -q "run_dir: $TMP_DIR/home/.agent-browser/assist/https___foxcode_rjj_cc/foxcode-main"

if RUNTIME_STUB_DIR="$TMP_DIR/runtime" AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assisted-session.sh" capture --run-dir "$TMP_DIR" --manifest-root "$TMP_DIR/manifests" --origin "https://example.com" >/dev/null 2>&1; then
  echo "expected capture without a verified browser to fail"
  exit 1
fi

mkdir -p "$TMP_DIR/runtime"
touch "$TMP_DIR/runtime/running" "$TMP_DIR/runtime/verified"
RUNTIME_STUB_DIR="$TMP_DIR/runtime" AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assisted-session.sh" capture --run-dir "$TMP_DIR" --manifest-root "$TMP_DIR/manifests" --origin "https://example.com" --block-reason login-wall >/dev/null
"$BASE_DIR/session-manifest.sh" show --root "$TMP_DIR/manifests" --origin "https://example.com" --session-key default | grep -q '"block_reason": "login-wall"'

RUNTIME_STUB_TARGETS_JSON='[
  {"id":"page-login","type":"page","url":"https://example.com/login"},
  {"id":"page-foxcode","type":"page","url":"https://foxcode.rjj.cc/api-keys"},
  {"id":"page-other","type":"page","url":"https://news.ycombinator.com"}
]' \
RUNTIME_STUB_DIR="$TMP_DIR/runtime" AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assisted-session.sh" capture --run-dir "$TMP_DIR" --manifest-root "$TMP_DIR/fox-manifests" --origin "https://foxcode.rjj.cc" >/dev/null
"$BASE_DIR/session-manifest.sh" show --root "$TMP_DIR/fox-manifests" --origin "https://foxcode.rjj.cc" --session-key default | grep -q '"target_id": "page-foxcode"'

mkdir -p "$TMP_DIR/override-run"
cat >"$TMP_DIR/override-run/assist.env" <<EOF
URL=https://example.com
RUN_DIR=$TMP_DIR/override-run
MANIFEST_ROOT=$TMP_DIR/wrong-root
NOVNC_PORT=6080
VNC_PORT=5900
PROFILE_DIR=$TMP_DIR/runtime/profile
EOF
RUNTIME_STUB_DIR="$TMP_DIR/runtime" AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assisted-session.sh" capture --run-dir "$TMP_DIR/override-run" --manifest-root "$TMP_DIR/override-manifests" --origin "https://override.example.com" --session-key override-check >/dev/null
"$BASE_DIR/session-manifest.sh" show --root "$TMP_DIR/override-manifests" --origin "https://override.example.com" --session-key override-check | grep -q '"session_key": "override-check"'

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/runtime" "$TMP_DIR/novnc"
cat >"$TMP_DIR/bin/x11vnc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${ASSIST_STUB_STATE_DIR:?}/x11vnc.args"
sleep 30
EOF
cat >"$TMP_DIR/bin/websockify" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${ASSIST_STUB_STATE_DIR:?}/websockify.args"
sleep 30
EOF
chmod +x "$TMP_DIR/bin/x11vnc" "$TMP_DIR/bin/websockify"

python3 -m http.server 5900 --bind 127.0.0.1 >/dev/null 2>&1 &
PORT_A_PID=$!
python3 -m http.server 6080 --bind 127.0.0.1 >/dev/null 2>&1 &
PORT_B_PID=$!
trap 'kill "$PORT_A_PID" "$PORT_B_PID" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

ASSIST_STUB_STATE_DIR="$TMP_DIR" \
AGENT_BROWSER_NOVNC_WEB_ROOT="$TMP_DIR/novnc" \
PATH="$TMP_DIR/bin:$PATH" \
RUNTIME_STUB_DIR="$TMP_DIR/runtime" \
AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/runtime-stub.sh" \
  "$BASE_DIR/assisted-session.sh" start --run-dir "$TMP_DIR/assist-run" --url "https://foxcode.rjj.cc/api-keys" >/dev/null

grep -Eq '(^| )-rfbport (590[1-9]|59[1-9][0-9]|6[0-9]{3,})( |$)' "$TMP_DIR/x11vnc.args"
grep -Eq '0.0.0.0:(608[1-9]|60[89][0-9]|6[1-9][0-9]{2,})' "$TMP_DIR/websockify.args"
"$BASE_DIR/assisted-session.sh" stop --run-dir "$TMP_DIR/assist-run" >/dev/null
