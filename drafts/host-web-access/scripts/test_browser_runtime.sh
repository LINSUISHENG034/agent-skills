#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pick_free_port() {
  python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

start_port_blocker() {
  local port="$1"
  local pid_file="$2"
  python3 - "$port" "$pid_file" <<'PY' &
import socket
import sys
import time

port = int(sys.argv[1])
pid_file = sys.argv[2]

sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", port))
sock.listen(1)
with open(pid_file, "w", encoding="utf-8") as handle:
    handle.write(str(__import__("os").getpid()))
while True:
    time.sleep(0.2)
PY
  STARTED_BLOCKER_PID=$!
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$pid_file" ] && break
    sleep 0.1
  done
}

cat >"$TMP_DIR/cdp-stub.py" <<'EOF'
#!/usr/bin/env python3
import json
import sys

args = sys.argv[1:]
check = args[args.index("--check") + 1]
if check == "challenge":
    print(json.dumps({"hasChallenge": True, "indicators": ["turnstile"], "title": "Verify you are human", "url": "https://example.com"}))
elif check == "login-wall":
    print(json.dumps({"hasLoginWall": True, "loginHits": ["Sign in"], "title": "Sign in", "url": "https://example.com/login"}))
else:
    print(json.dumps({"title": "Example", "url": "https://example.com", "bodySnippet": "hello"}))
EOF
chmod +x "$TMP_DIR/cdp-stub.py"

status_output="$("$BASE_DIR/browser-runtime.sh" status --run-dir "$TMP_DIR")"
printf '%s\n' "$status_output" | grep -q "status: missing"

mkdir -p "$TMP_DIR/stale-run"
cat >"$TMP_DIR/stale-run/runtime.env" <<EOF
MODE=headless
ORIGIN=https://example.com
SESSION_KEY=stale
INITIAL_URL=https://example.com
PROFILE_DIR=$TMP_DIR/stale-profile
RUN_DIR=$TMP_DIR/stale-run
LOG_DIR=$TMP_DIR/stale-logs
CDP_HOST=127.0.0.1
CDP_PORT=24554
DISPLAY_NUM=88
BROWSER_CMD=$TMP_DIR/bin/browser-stub
BROWSER_COMMAND=$TMP_DIR/bin/browser-stub\ --headless=new
BROWSER_PID=999999
STATE=running
EOF
stale_status="$("$BASE_DIR/browser-runtime.sh" status --run-dir "$TMP_DIR/stale-run")"
printf '%s\n' "$stale_status" | grep -q "status: stopped"
printf '%s\n' "$stale_status" | grep -q "cdp_host: 127.0.0.1"

list_output="$("$BASE_DIR/browser-runtime.sh" list-targets --run-dir "$TMP_DIR")"
printf '%s\n' "$list_output" | grep -q '^\[\]$'

"$BASE_DIR/cleanup-host-runtime.sh" --run-dir "$TMP_DIR"
post_cleanup="$("$BASE_DIR/browser-runtime.sh" status --run-dir "$TMP_DIR")"
printf '%s\n' "$post_cleanup" | grep -q "status: closed"

mkdir -p "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/browser-stub" <<'EOF'
#!/usr/bin/env python3
import http.server
import json
import os
import signal
import socketserver
import sys

args = sys.argv[1:]
port = None
for item in args:
    if item.startswith("--remote-debugging-port="):
        port = int(item.split("=", 1)[1])
        break
if port is None:
    raise SystemExit("missing --remote-debugging-port")

json.dump({"args": args}, open(sys.argv[0] + ".args.json", "w", encoding="utf-8"))

targets_file = os.environ.get("BROWSER_STUB_TARGETS_FILE")
targets_payload = [{
    "id": "page-login",
    "type": "page",
    "url": "https://example.com/login",
    "title": "Login",
    "webSocketDebuggerUrl": f"ws://127.0.0.1:{port}/devtools/page/1",
}, {
    "id": "worker-1",
    "type": "service_worker",
    "url": "https://example.com/sw.js",
    "title": "SW",
    "webSocketDebuggerUrl": f"ws://127.0.0.1:{port}/devtools/page/worker-1",
}, {
    "id": "page-account",
    "type": "page",
    "url": "https://example.com/account",
    "title": "Account",
    "webSocketDebuggerUrl": f"ws://127.0.0.1:{port}/devtools/page/2",
}, {
    "id": "page-default",
    "type": "page",
    "url": "https://example.com",
    "title": "Example",
    "webSocketDebuggerUrl": f"ws://127.0.0.1:{port}/devtools/page/1",
}]
if targets_file:
    with open(targets_file, "r", encoding="utf-8") as handle:
        targets_payload = json.load(handle)

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_GET(self):
        if self.path == "/json/version":
            payload = {"Browser": "stub", "webSocketDebuggerUrl": f"ws://127.0.0.1:{port}/devtools/page/1"}
        elif self.path == "/json/list":
            payload = targets_payload
        else:
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

httpd = socketserver.TCPServer(("127.0.0.1", port), Handler)

def shutdown(*_args):
    httpd.shutdown()

signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)
httpd.serve_forever()
EOF
chmod +x "$TMP_DIR/bin/browser-stub"

set +e
missing_output="$("$BASE_DIR/browser-runtime.sh" start \
  --run-dir "$TMP_DIR/missing-run" \
  --profile-dir "$TMP_DIR/missing-profile" \
  --url "https://example.com" \
  --origin "https://example.com" \
  --session-key missing \
  --mode headless \
  --browser "$TMP_DIR/bin/does-not-exist" 2>&1)"
missing_status=$?
set -e
[ "$missing_status" -ne 0 ]
printf '%s\n' "$missing_output" | grep -q "missing browser executable"

runtime_port="$(pick_free_port)"
start_output="$("$BASE_DIR/browser-runtime.sh" start \
  --run-dir "$TMP_DIR/task-run" \
  --profile-dir "$TMP_DIR/task-profile" \
  --url "https://example.com" \
  --origin "https://example.com" \
  --session-key default \
  --mode headless \
  --cdp-port "$runtime_port" \
  --browser "$TMP_DIR/bin/browser-stub")"
printf '%s\n' "$start_output" | grep -q "status: running"
printf '%s\n' "$start_output" | grep -q "profile_dir: $TMP_DIR/task-profile"
printf '%s\n' "$start_output" | grep -q "cdp_host: 127.0.0.1"
printf '%s\n' "$start_output" | grep -q "browser_command: "

selected_target="$(
  "$BASE_DIR/browser-runtime.sh" select-target \
    --run-dir "$TMP_DIR/task-run" \
    --origin "https://example.com" \
    --target-url "https://example.com/account"
)"
printf '%s\n' "$selected_target" | grep -q '^page-account$'

off_origin_target="$(
  "$BASE_DIR/browser-runtime.sh" select-target \
    --origin "https://example.com" \
    --target-url "https://example.com/account" \
    --targets-json '[{"id":"page-other","type":"page","url":"https://unrelated.example/page"}]'
)"
[ -z "$off_origin_target" ]

challenge_output="$(AGENT_BROWSER_CDP_EVAL="$TMP_DIR/cdp-stub.py" \
  "$BASE_DIR/browser-runtime.sh" check-page --run-dir "$TMP_DIR/task-run" --cdp-port "$runtime_port" --target-id TARGET_ID --check challenge)"
printf '%s\n' "$challenge_output" | grep -q '"hasChallenge": true'
login_output="$(AGENT_BROWSER_CDP_EVAL="$TMP_DIR/cdp-stub.py" \
  "$BASE_DIR/browser-runtime.sh" check-page --run-dir "$TMP_DIR/task-run" --cdp-port "$runtime_port" --target-id TARGET_ID --check login-wall)"
printf '%s\n' "$login_output" | grep -q '"hasLoginWall": true'
page_info_output="$(AGENT_BROWSER_CDP_EVAL="$TMP_DIR/cdp-stub.py" \
  "$BASE_DIR/browser-runtime.sh" check-page --run-dir "$TMP_DIR/task-run" --cdp-port "$runtime_port" --target-id TARGET_ID --check page-info)"
printf '%s\n' "$page_info_output" | grep -q '"title": "Example"'

mkdir -p "$TMP_DIR/manifests"
"$BASE_DIR/session-manifest.sh" write \
  --root "$TMP_DIR/manifests" \
  --origin "https://example.com" \
  --session-key stale \
  --state ready \
  --browser-pid 999999 >/dev/null
set +e
verify_stale_output="$("$BASE_DIR/browser-runtime.sh" verify --run-dir "$TMP_DIR/task-run" --manifest-root "$TMP_DIR/manifests" --origin "https://example.com" --session-key stale 2>&1)"
verify_stale_status=$?
set -e
[ "$verify_stale_status" -ne 0 ]
printf '%s\n' "$verify_stale_output" | grep -q "browser is not running for manifest stale"
stale_manifest_state="$("$BASE_DIR/session-manifest.sh" show --root "$TMP_DIR/manifests" --origin "https://example.com" --session-key stale | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
[ "$stale_manifest_state" = "stale" ]

"$BASE_DIR/session-manifest.sh" write \
  --root "$TMP_DIR/manifests" \
  --origin "https://example.com" \
  --session-key bad-target \
  --state ready \
  --browser-pid "$(
    python3 - "$TMP_DIR/task-run/runtime.env" <<'PY'
import shlex
import sys

state = {}
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    for raw in handle:
        raw = raw.strip()
        if not raw or "=" not in raw:
            continue
        k, v = raw.split("=", 1)
        state[k] = shlex.split(v)[0] if v else ""
print(state.get("BROWSER_PID", ""))
PY
  )" \
  --cdp-port "$runtime_port" \
  --target-id "missing-target-id" >/dev/null
set +e
verify_target_output="$("$BASE_DIR/browser-runtime.sh" verify --run-dir "$TMP_DIR/task-run" --manifest-root "$TMP_DIR/manifests" --origin "https://example.com" --session-key bad-target 2>&1)"
verify_target_status=$?
set -e
[ "$verify_target_status" -ne 0 ]
printf '%s\n' "$verify_target_output" | grep -q "target_id is no longer present for manifest bad-target"
bad_target_manifest_state="$("$BASE_DIR/session-manifest.sh" show --root "$TMP_DIR/manifests" --origin "https://example.com" --session-key bad-target | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
[ "$bad_target_manifest_state" = "stale" ]

unreachable_cdp_port="$(pick_free_port)"
"$BASE_DIR/session-manifest.sh" write \
  --root "$TMP_DIR/manifests" \
  --origin "https://example.com" \
  --session-key bad-cdp \
  --state ready \
  --browser-pid "$(
    python3 - "$TMP_DIR/task-run/runtime.env" <<'PY'
import shlex
import sys

state = {}
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    for raw in handle:
        raw = raw.strip()
        if not raw or "=" not in raw:
            continue
        k, v = raw.split("=", 1)
        state[k] = shlex.split(v)[0] if v else ""
print(state.get("BROWSER_PID", ""))
PY
  )" \
  --cdp-port "$unreachable_cdp_port" >/dev/null
set +e
verify_cdp_output="$("$BASE_DIR/browser-runtime.sh" verify --run-dir "$TMP_DIR/task-run" --manifest-root "$TMP_DIR/manifests" --origin "https://example.com" --session-key bad-cdp 2>&1)"
verify_cdp_status=$?
set -e
[ "$verify_cdp_status" -ne 0 ]
printf '%s\n' "$verify_cdp_output" | grep -q "CDP endpoint is unreachable for manifest bad-cdp"
bad_cdp_manifest_state="$("$BASE_DIR/session-manifest.sh" show --root "$TMP_DIR/manifests" --origin "https://example.com" --session-key bad-cdp | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
[ "$bad_cdp_manifest_state" = "stale" ]
if printf '%s\n' "$verify_cdp_output" | grep -q "Traceback"; then
  echo "expected controlled verify error without traceback"
  exit 1
fi

grep -q '^CDP_HOST=127.0.0.1$' "$TMP_DIR/task-run/runtime.env"
grep -q '^STATE=running$' "$TMP_DIR/task-run/runtime.env"
grep -q '^BROWSER_COMMAND=' "$TMP_DIR/task-run/runtime.env"
grep -q '^BROWSER_PID=' "$TMP_DIR/task-run/runtime.env"
python3 - "$TMP_DIR/bin/browser-stub.args.json" "$runtime_port" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
args = payload["args"]
required = {
    "--headless=new",
    "--no-first-run",
    "--no-default-browser-check",
    "--user-data-dir=" + sys.argv[1].replace("/bin/browser-stub.args.json", "/task-profile"),
    "--remote-debugging-address=127.0.0.1",
    "--remote-debugging-port=" + sys.argv[2],
    "https://example.com",
}
missing = sorted(required.difference(args))
if missing:
    raise SystemExit(f"missing browser args: {missing}")
PY

"$BASE_DIR/cleanup-host-runtime.sh" --run-dir "$TMP_DIR/task-run"
closed_output="$("$BASE_DIR/browser-runtime.sh" status --run-dir "$TMP_DIR/task-run" --origin "https://example.com" --session-key default)"
printf '%s\n' "$closed_output" | grep -q "status: closed"
[ ! -f "$TMP_DIR/task-run/browser.pid" ]

mkdir -p "$TMP_DIR/lock-profile-live" "$TMP_DIR/lock-profile-stale"
sleep 60 &
live_lock_pid=$!
(
  cd "$TMP_DIR/lock-profile-live"
  ln -s "stub-${live_lock_pid}" SingletonLock
)
live_lock_port="$(pick_free_port)"
"$BASE_DIR/browser-runtime.sh" start \
  --run-dir "$TMP_DIR/live-lock-run" \
  --profile-dir "$TMP_DIR/lock-profile-live" \
  --url "https://example.com" \
  --origin "https://example.com" \
  --session-key live-lock \
  --mode headless \
  --cdp-port "$live_lock_port" \
  --browser "$TMP_DIR/bin/browser-stub" >/dev/null
test -L "$TMP_DIR/lock-profile-live/SingletonLock"
"$BASE_DIR/cleanup-host-runtime.sh" --run-dir "$TMP_DIR/live-lock-run"
kill "$live_lock_pid" 2>/dev/null || true

(
  cd "$TMP_DIR/lock-profile-stale"
  ln -s "stub-999999" SingletonLock
)
stale_lock_port="$(pick_free_port)"
"$BASE_DIR/browser-runtime.sh" start \
  --run-dir "$TMP_DIR/stale-lock-run" \
  --profile-dir "$TMP_DIR/lock-profile-stale" \
  --url "https://example.com" \
  --origin "https://example.com" \
  --session-key stale-lock \
  --mode headless \
  --cdp-port "$stale_lock_port" \
  --browser "$TMP_DIR/bin/browser-stub" >/dev/null
test ! -e "$TMP_DIR/lock-profile-stale/SingletonLock"
"$BASE_DIR/cleanup-host-runtime.sh" --run-dir "$TMP_DIR/stale-lock-run"

mkdir -p "$TMP_DIR/fakebin" "$TMP_DIR/x11-sockets"
cat >"$TMP_DIR/fakebin/Xvfb" <<'EOF'
#!/usr/bin/env bash
display="${1#:}"
socket_dir="${AGENT_BROWSER_X11_SOCKET_DIR:-/tmp/.X11-unix}"
mkdir -p "$socket_dir"
touch "$socket_dir/X${display}"
trap 'rm -f "$socket_dir/X${display}"; exit 0' TERM INT EXIT
sleep 300
EOF
chmod +x "$TMP_DIR/fakebin/Xvfb"
cat >"$TMP_DIR/fakebin/xdpyinfo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP_DIR/fakebin/xdpyinfo"
touch "$TMP_DIR/x11-sockets/X88"

blocked_port="$(pick_free_port)"
port_blocker_pid_file="$TMP_DIR/blocked-port.pid"
start_port_blocker "$blocked_port" "$port_blocker_pid_file"
blocked_pid="$STARTED_BLOCKER_PID"
PATH="$TMP_DIR/fakebin:$PATH" HOST_WEB_ACCESS_CDP_PORT="$blocked_port" AGENT_BROWSER_X11_SOCKET_DIR="$TMP_DIR/x11-sockets" "$BASE_DIR/browser-runtime.sh" start \
  --run-dir "$TMP_DIR/auto-run" \
  --profile-dir "$TMP_DIR/auto-profile" \
  --url "https://example.com" \
  --origin "https://example.com" \
  --session-key auto \
  --mode gui \
  --browser "$TMP_DIR/bin/browser-stub" >/dev/null
kill "$blocked_pid" 2>/dev/null || true

auto_status="$("$BASE_DIR/browser-runtime.sh" status --run-dir "$TMP_DIR/auto-run" --origin "https://example.com" --session-key auto)"
auto_port="$(printf '%s\n' "$auto_status" | awk -F': ' '/^cdp_port:/ {print $2}')"
auto_display="$(printf '%s\n' "$auto_status" | awk -F': ' '/^display:/ {print $2}')"
[ -n "$auto_port" ]
[ "$auto_port" != "$blocked_port" ]
[ "$auto_display" != ":88" ]
grep -q "^CDP_PORT=${auto_port}$" "$TMP_DIR/auto-run/runtime.env"
grep -q "^DISPLAY_NUM=${auto_display#:}$" "$TMP_DIR/auto-run/runtime.env"
"$BASE_DIR/cleanup-host-runtime.sh" --run-dir "$TMP_DIR/auto-run"
