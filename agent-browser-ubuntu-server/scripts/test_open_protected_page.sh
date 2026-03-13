#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/browser-runtime-stub.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MODE="${RUNTIME_STUB_MODE:-ready}"
STATE_FILE="${RUNTIME_STUB_STATE_FILE:-}"
case "${1:-}" in
  verify)
    exit 1
    ;;
  status)
    if [ "$MODE" = "verify-fails-running" ]; then
      cat <<OUT
runtime: running
mode: gui
url: https://foxcode.rjj.cc/api-keys
profile_dir: /tmp/profile
run_dir: /tmp/run
cdp_port: 19222
browser_pid: 12345
xvfb_pid: 67890
display: :88
OUT
    else
      cat <<OUT
runtime: stopped
mode: gui
url: https://foxcode.rjj.cc/api-keys
profile_dir: /tmp/profile
run_dir: /tmp/run
cdp_port: 19222
browser_pid:
xvfb_pid:
display: :88
OUT
    fi
    ;;
  start)
    if [ "$MODE" = "verify-fails-running" ]; then
      echo "[browser-runtime] ERROR: browser runtime already running; use stop or status first" >&2
      exit 1
    fi
    echo "runtime started"
    ;;
  list-targets)
    echo '[{"id":"page-foxcode","type":"page","url":"https://foxcode.rjj.cc/api-keys"}]'
    ;;
  select-target)
    echo "page-foxcode"
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
      case "$MODE:$check" in
        ready:challenge|login-wall:challenge)
          echo '{"hasChallenge":false}'
          ;;
        transient-login:challenge)
          echo '{"hasChallenge":false}'
          ;;
        ready:login-wall)
          echo '{"hasLoginWall":false}'
          ;;
        login-wall:login-wall)
          echo '{"hasLoginWall":true}'
          ;;
        transient-login:login-wall)
          if [ -n "$STATE_FILE" ]; then
            count=0
            if [ -f "$STATE_FILE" ]; then
              count="$(cat "$STATE_FILE")"
            fi
            count=$((count + 1))
            printf '%s\n' "$count" >"$STATE_FILE"
            if [ "$count" -ge 2 ]; then
              echo '{"hasLoginWall":true}'
            else
              echo '{"hasLoginWall":false}'
            fi
          else
            echo '{"hasLoginWall":false}'
          fi
          ;;
        *:page-info)
        if [ "$MODE" = "transient-login" ] && [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" -lt 2 ]; then
          echo '{"title":"","url":"about:blank","bodySnippet":""}'
        else
          echo '{"title":"API密钥管理 - NEW CLI","url":"https://foxcode.rjj.cc/api-keys","bodySnippet":"余额基数"}'
        fi
        ;;
      *)
        echo '{"hasChallenge":false,"hasLoginWall":false}'
        ;;
    esac
    ;;
  *)
    echo "unexpected runtime command: $1" >&2
    exit 1
    ;;
esac
EOF

cat >"$TMP_DIR/assisted-stub.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${ASSISTED_STUB_LOG:?}"
case "${1:-}" in
  start)
    echo '[assisted-session] noVNC URL: http://127.0.0.1:6081/vnc.html?autoconnect=1&resize=remote'
    ;;
  status)
    cat <<OUT
assisted_session: running
run_dir: /tmp/assist
runtime_run_dir: /tmp/runtime
novnc_url: http://127.0.0.1:6081/vnc.html?autoconnect=1&resize=remote
OUT
    ;;
  *)
    echo "unexpected assisted command: $1" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$TMP_DIR/browser-runtime-stub.sh" "$TMP_DIR/assisted-stub.sh"

ready_output="$(
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/browser-runtime-stub.sh" \
  AGENT_BROWSER_ASSISTED_HELPER="$TMP_DIR/assisted-stub.sh" \
  ASSISTED_STUB_LOG="$TMP_DIR/assisted.log" \
  "$BASE_DIR/open-protected-page.sh" \
    --url 'https://foxcode.rjj.cc/api-keys' \
    --origin 'https://foxcode.rjj.cc' \
    --session-key foxcode-main
)"
printf '%s\n' "$ready_output" | grep -q '"status": "ready"'
printf '%s\n' "$ready_output" | grep -q '"targetId": "page-foxcode"'
if [ -f "$TMP_DIR/assisted.log" ]; then
  echo "assisted flow should not start for ready pages"
  exit 1
fi

login_output="$(
  RUNTIME_STUB_MODE="login-wall" \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/browser-runtime-stub.sh" \
  AGENT_BROWSER_ASSISTED_HELPER="$TMP_DIR/assisted-stub.sh" \
  ASSISTED_STUB_LOG="$TMP_DIR/assisted.log" \
  "$BASE_DIR/open-protected-page.sh" \
    --url 'https://foxcode.rjj.cc/api-keys' \
    --origin 'https://foxcode.rjj.cc' \
    --session-key foxcode-main
)"
printf '%s\n' "$login_output" | grep -q '"status": "needs-user"'
printf '%s\n' "$login_output" | grep -q 'http://127.0.0.1:6081/vnc.html'
grep -q '^start ' "$TMP_DIR/assisted.log"

rm -f "$TMP_DIR/assisted.log" "$TMP_DIR/runtime-state"
transient_output="$(
  RUNTIME_STUB_MODE="transient-login" \
  RUNTIME_STUB_STATE_FILE="$TMP_DIR/runtime-state" \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/browser-runtime-stub.sh" \
  AGENT_BROWSER_ASSISTED_HELPER="$TMP_DIR/assisted-stub.sh" \
  ASSISTED_STUB_LOG="$TMP_DIR/assisted.log" \
  "$BASE_DIR/open-protected-page.sh" \
    --url 'https://foxcode.rjj.cc/api-keys' \
    --origin 'https://foxcode.rjj.cc' \
    --session-key foxcode-main
)"
printf '%s\n' "$transient_output" | grep -q '"status": "needs-user"'
printf '%s\n' "$transient_output" | grep -q '"reason": "login-wall"'

running_output="$(
  RUNTIME_STUB_MODE="verify-fails-running" \
  AGENT_BROWSER_RUNTIME_HELPER="$TMP_DIR/browser-runtime-stub.sh" \
  AGENT_BROWSER_ASSISTED_HELPER="$TMP_DIR/assisted-stub.sh" \
  ASSISTED_STUB_LOG="$TMP_DIR/assisted.log" \
  "$BASE_DIR/open-protected-page.sh" \
    --url 'https://foxcode.rjj.cc/api-keys' \
    --origin 'https://foxcode.rjj.cc' \
    --session-key foxcode-main
)"
printf '%s\n' "$running_output" | grep -q '"status": "ready"'
