#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  open-host-page.sh --url URL [--session-key KEY] [--task-mode MODE] [--expected-action ACTION] [--run-dir DIR] [--manifest-root DIR]

Options:
  --url URL
  --session-key KEY
  --task-mode MODE           latest|article|dynamic|protected|interactive|login-required|host-browser
  --expected-action ACTION   lightweight|browser
  --run-dir DIR
  --manifest-root DIR
EOF
}

log_error() {
  printf '[open-host-page] ERROR: %s\n' "$*" >&2
}

route_for_mode() {
  local mode="$1"
  "$ROUTE_HELPER" "--$mode"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTE_HELPER="${HOST_WEB_ACCESS_ROUTE_HELPER:-$SCRIPT_DIR/route-web-task.sh}"
BROWSER_RUNTIME_HELPER="${HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER:-$SCRIPT_DIR/browser-runtime.sh}"
ASSIST_HELPER="${HOST_WEB_ACCESS_ASSIST_HELPER:-$SCRIPT_DIR/assist-lan-session.sh}"
CLEANUP_HELPER="${HOST_WEB_ACCESS_CLEANUP_HELPER:-$SCRIPT_DIR/cleanup-host-runtime.sh}"
task_mode="latest"
expected_action=""
url=""
session_key="default"
run_dir=""
manifest_root=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      url="$2"
      shift 2
      ;;
    --session-key)
      session_key="$2"
      shift 2
      ;;
    --task-mode)
      task_mode="$2"
      shift 2
      ;;
    --expected-action)
      expected_action="$2"
      shift 2
      ;;
    --run-dir)
      run_dir="$2"
      shift 2
      ;;
    --manifest-root)
      manifest_root="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

[ -n "$url" ] || {
  log_error "--url is required"
  usage
  exit 1
}

run_dir="${run_dir:-$HOME/.agent-browser/run/$session_key}"
profile_dir="$HOME/.agent-browser/profiles/$session_key"
manifest_root="${manifest_root:-$HOME/.agent-browser}"

route_output="$(route_for_mode "$task_mode")"
route="$(printf '%s\n' "$route_output" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["route"])')"
reason="$(printf '%s\n' "$route_output" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["reason"])')"
needs_browser="$(printf '%s\n' "$route_output" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["needs_browser"])')"

if [ -n "$expected_action" ]; then
  if [ "$expected_action" = "browser" ] && [ "$route" != "browser" ]; then
    log_error "expected browser route but got $route"
    exit 1
  elif [ "$expected_action" = "lightweight" ] && [ "$route" = "browser" ]; then
    log_error "expected lightweight route but got browser"
    exit 1
  fi
fi

if [ "$route" != "browser" ]; then
  printf 'route: %s reason: %s needs_browser: %s\n' "$route" "$reason" "$needs_browser"
  exit 0
fi

cleanup_browser() {
  "$CLEANUP_HELPER" --run-dir "$run_dir"
}

trap cleanup_browser EXIT

"$BROWSER_RUNTIME_HELPER" start \
  --run-dir "$run_dir" \
  --profile-dir "$profile_dir" \
  --origin "$url" \
  --session-key "$session_key"

status_output="$("$BROWSER_RUNTIME_HELPER" status --run-dir "$run_dir")"
if ! printf '%s\n' "$status_output" | grep -q 'status: running'; then
  "$BROWSER_RUNTIME_HELPER" ensure-browser --run-dir "$run_dir" --profile-dir "$profile_dir" --origin "$url" --session-key "$session_key" >/dev/null
  status_output="$("$BROWSER_RUNTIME_HELPER" status --run-dir "$run_dir")"
fi

if ! printf '%s\n' "$status_output" | grep -q 'status: running'; then
  "$ASSIST_HELPER" start \
    --run-dir "$run_dir" \
    --origin "$url" \
    --session-key "$session_key" \
    --profile-dir "$profile_dir"
  "$ASSIST_HELPER" capture \
    --run-dir "$run_dir" \
    --origin "$url" \
    --session-key "$session_key" \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root"
  "$ASSIST_HELPER" stop --run-dir "$run_dir"
fi

cleanup_browser
trap - EXIT
