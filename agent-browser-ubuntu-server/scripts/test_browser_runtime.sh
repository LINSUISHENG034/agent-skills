#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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
printf '%s\n' "$status_output" | grep -q "stopped"
list_output="$("$BASE_DIR/browser-runtime.sh" list-targets --run-dir "$TMP_DIR")"
printf '%s\n' "$list_output" | grep -q '^\[\]$'
if "$BASE_DIR/browser-runtime.sh" attach --run-dir "$TMP_DIR" --origin "https://example.com" --session-key "missing" >/dev/null 2>&1; then
  echo "expected attach with missing session to fail"
  exit 1
fi
"$BASE_DIR/session-manifest.sh" write \
  --root "$TMP_DIR/manifests" \
  --origin "https://example.com" \
  --session-key "stale" \
  --state ready \
  --browser-pid 999999 >/dev/null
if "$BASE_DIR/browser-runtime.sh" verify --run-dir "$TMP_DIR" --manifest-root "$TMP_DIR/manifests" --origin "https://example.com" --session-key "stale" >/dev/null 2>&1; then
  echo "expected verify with dead browser to fail"
  exit 1
fi
challenge_output="$(AGENT_BROWSER_CDP_EVAL="$TMP_DIR/cdp-stub.py" \
  "$BASE_DIR/browser-runtime.sh" check-page --run-dir "$TMP_DIR" --cdp-port 19222 --target-id TARGET_ID --check challenge)"
printf '%s\n' "$challenge_output" | grep -q '"hasChallenge": true'
login_output="$(AGENT_BROWSER_CDP_EVAL="$TMP_DIR/cdp-stub.py" \
  "$BASE_DIR/browser-runtime.sh" check-page --run-dir "$TMP_DIR" --cdp-port 19222 --target-id TARGET_ID --check login-wall)"
printf '%s\n' "$login_output" | grep -q '"hasLoginWall": true'

mkdir -p "$TMP_DIR/override-run"
cat >"$TMP_DIR/override-run/runtime.env" <<EOF
MODE=gui
INITIAL_URL=https://stale.example
PROFILE_DIR=$TMP_DIR/stale-profile
RUN_DIR=$TMP_DIR/override-run
LOG_DIR=$TMP_DIR/stale-logs
CDP_PORT=29999
DISPLAY_NUM=55
BROWSER_CMD=/usr/bin/google-chrome
EOF
override_status="$("$BASE_DIR/browser-runtime.sh" status \
  --run-dir "$TMP_DIR/override-run" \
  --url "https://override.example" \
  --profile-dir "$TMP_DIR/override-profile" \
  --cdp-port 24444 \
  --display 99 \
  --mode headless)"
printf '%s\n' "$override_status" | grep -q 'url: https://override.example'
printf '%s\n' "$override_status" | grep -q "profile_dir: $TMP_DIR/override-profile"
printf '%s\n' "$override_status" | grep -q 'cdp_port: 24444'
printf '%s\n' "$override_status" | grep -q 'mode: headless'
