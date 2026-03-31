#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_GET(self):
        if self.path == "/json/version":
            payload = {"Browser": "stub", "webSocketDebuggerUrl": f"ws://127.0.0.1:{port}/devtools/page/1"}
        elif self.path == "/json/list":
            payload = [{
                "id": "page-1",
                "type": "page",
                "url": "https://example.com",
                "title": "Example",
                "webSocketDebuggerUrl": f"ws://127.0.0.1:{port}/devtools/page/1",
            }]
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
printf '%s\n' "$start_output" | grep -q "cdp_host: 127.0.0.1"
printf '%s\n' "$start_output" | grep -q "browser_command: "

grep -q '^CDP_HOST=127.0.0.1$' "$TMP_DIR/task-run/runtime.env"
grep -q '^STATE=running$' "$TMP_DIR/task-run/runtime.env"
grep -q '^BROWSER_COMMAND=' "$TMP_DIR/task-run/runtime.env"
grep -q '^BROWSER_PID=' "$TMP_DIR/task-run/runtime.env"
python3 - "$TMP_DIR/bin/browser-stub.args.json" <<'PY'
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
    "--remote-debugging-port=24555",
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
