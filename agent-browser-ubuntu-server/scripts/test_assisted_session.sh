#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/runtime-stub.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${RUNTIME_STUB_DIR:?}"
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
      echo '[{"id":"page-1","type":"page","url":"https://example.com"}]'
    else
      echo '[]'
    fi
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
