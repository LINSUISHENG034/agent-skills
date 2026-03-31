#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/runtime-common.sh"

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

die() {
  printf '[open-host-page] ERROR: %s\n' "$*" >&2
  exit 1
}

route_for_mode() {
  local mode="$1"
  "$ROUTE_HELPER" "--$mode"
}

json_field() {
  local field="$1"
  local payload="$2"
  python3 - "$field" "$payload" <<'PY'
import json
import sys

field = sys.argv[1]
payload = json.loads(sys.argv[2])
value = payload.get(field)
if isinstance(value, bool):
    print("true" if value else "false")
elif value is not None:
    print(value)
PY
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTE_HELPER="${HOST_WEB_ACCESS_ROUTE_HELPER:-$SCRIPT_DIR/route-web-task.sh}"
BROWSER_RUNTIME_HELPER="${HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER:-$SCRIPT_DIR/browser-runtime.sh}"
ASSIST_HELPER="${HOST_WEB_ACCESS_ASSIST_HELPER:-$SCRIPT_DIR/assist-lan-session.sh}"
CLEANUP_HELPER="${HOST_WEB_ACCESS_CLEANUP_HELPER:-$SCRIPT_DIR/cleanup-host-runtime.sh}"
PROFILE_HELPER="${HOST_WEB_ACCESS_PROFILE_HELPER:-$SCRIPT_DIR/profile-resolution.sh}"

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
      die "unknown option: $1"
      ;;
  esac
done

[ -n "$url" ] || die "--url is required"

origin="$(derive_origin "$url")"
base_root="${HOME}/.agent-browser"
manifest_root="${manifest_root:-$base_root}"
run_dir="${run_dir:-$(runtime_scoped_path "$base_root" run "$origin" "$session_key")}"

route_output="$(route_for_mode "$task_mode")"
route="$(json_field route "$route_output")"
reason="$(json_field reason "$route_output")"
needs_browser="$(json_field needs_browser "$route_output")"

if [ -n "$expected_action" ]; then
  if [ "$expected_action" = "browser" ] && [ "$route" != "browser" ]; then
    die "expected browser route but got $route"
  fi
  if [ "$expected_action" = "lightweight" ] && [ "$route" = "browser" ]; then
    die "expected lightweight route but got browser"
  fi
fi

if [ "$route" != "browser" ]; then
  printf 'route: %s reason: %s needs_browser: %s\n' "$route" "$reason" "$needs_browser"
  exit 0
fi

resolved_profile="$(
  "$PROFILE_HELPER" resolve \
    --root "$base_root" \
    --manifest-root "$manifest_root" \
    --origin "$origin" \
    --session-key "$session_key"
)"
profile_dir="$(json_field profile_dir "$resolved_profile")"
[ -n "$profile_dir" ] || die "profile-resolution did not return profile_dir"

cleanup_browser() {
  "$CLEANUP_HELPER" --run-dir "$run_dir" >/dev/null 2>&1 || true
}

trap cleanup_browser EXIT

if ! "$BROWSER_RUNTIME_HELPER" ensure-browser --run-dir "$run_dir" >/dev/null; then
  die "browser dependency check failed"
fi

"$BROWSER_RUNTIME_HELPER" start \
  --run-dir "$run_dir" \
  --profile-dir "$profile_dir" \
  --url "$url" \
  --origin "$origin" \
  --session-key "$session_key" \
  --mode gui >/dev/null

status_output="$("$BROWSER_RUNTIME_HELPER" status --run-dir "$run_dir" --origin "$origin" --session-key "$session_key")"
if ! printf '%s\n' "$status_output" | grep -q '^status: running$'; then
  "$ASSIST_HELPER" start \
    --run-dir "$run_dir" \
    --origin "$origin" \
    --session-key "$session_key" \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" >/dev/null
  "$ASSIST_HELPER" capture \
    --run-dir "$run_dir" \
    --origin "$origin" \
    --session-key "$session_key" \
    --profile-dir "$profile_dir" \
    --manifest-root "$manifest_root" >/dev/null
  "$ASSIST_HELPER" stop --run-dir "$run_dir" >/dev/null
fi

printf 'route: %s reason: %s needs_browser: %s\n' "$route" "$reason" "$needs_browser"
