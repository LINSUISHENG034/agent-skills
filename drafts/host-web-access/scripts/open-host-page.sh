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
  --expected-action ACTION   search|fetch|browser (legacy lightweight alias accepted)
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

status_field() {
  local field="$1"
  local payload="$2"
  python3 - "$field" "$payload" <<'PY'
import sys

target = sys.argv[1]
for raw in sys.argv[2].splitlines():
    if ":" not in raw:
        continue
    key, value = raw.split(":", 1)
    if key.strip() == target:
        print(value.strip())
        break
PY
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

emit_result() {
  python3 - "$@" <<'PY'
import json
import sys

route, reason, needs_browser, origin, run_dir, profile_dir, runtime_status, page_status, target_id, recovery_attempted, assisted_session, lan_novnc_url = sys.argv[1:13]

payload = {
    "route": route,
    "reason": reason,
    "needs_browser": needs_browser == "true",
    "origin": origin,
}

if run_dir:
    payload["run_dir"] = run_dir
if profile_dir:
    payload["profile_dir"] = profile_dir
if runtime_status:
    payload["runtime_status"] = runtime_status
if page_status:
    payload["page_status"] = page_status
if target_id:
    payload["target_id"] = target_id
if recovery_attempted:
    payload["recovery_attempted"] = recovery_attempted == "true"
if assisted_session:
    payload["assisted_session"] = assisted_session == "true"
if lan_novnc_url:
    payload["lan_novnc_url"] = lan_novnc_url

print(json.dumps(payload))
PY
}

assert_expected_route() {
  case "$expected_action" in
    "")
      return 0
      ;;
    lightweight)
      if [ "$route" = "browser" ]; then
        die "route assertion failed before browser orchestration started: expected lightweight route but router returned browser"
      fi
      ;;
    search|fetch|browser)
      if [ "$route" != "$expected_action" ]; then
        die "route assertion failed before browser orchestration started: expected route $expected_action but router returned $route"
      fi
      ;;
    *)
      die "--expected-action must be search, fetch, browser, or legacy lightweight"
      ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTE_HELPER="${HOST_WEB_ACCESS_ROUTE_HELPER:-$SCRIPT_DIR/route-web-task.sh}"
BROWSER_RUNTIME_HELPER="${HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER:-$SCRIPT_DIR/browser-runtime.sh}"
ASSIST_HELPER="${HOST_WEB_ACCESS_ASSIST_HELPER:-$SCRIPT_DIR/assist-lan-session.sh}"
CLEANUP_HELPER="${HOST_WEB_ACCESS_CLEANUP_HELPER:-$SCRIPT_DIR/cleanup-host-runtime.sh}"
PROFILE_HELPER="${HOST_WEB_ACCESS_PROFILE_HELPER:-$SCRIPT_DIR/profile-resolution.sh}"
PAGE_OPS_HELPER="${HOST_WEB_ACCESS_PAGE_OPS_HELPER:-$SCRIPT_DIR/host-page-ops.py}"

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
assert_expected_route

if [ "$route" != "browser" ]; then
  emit_result "$route" "$reason" "$needs_browser" "$origin" "" "" "" "" "" "" "" ""
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
  if [ "${PRESERVE_RUNTIME_ON_EXIT:-false}" = "true" ]; then
    return 0
  fi
  "$CLEANUP_HELPER" --run-dir "$run_dir" >/dev/null 2>&1 || true
}

trap cleanup_browser EXIT

if ! "$BROWSER_RUNTIME_HELPER" ensure-browser --run-dir "$run_dir" >/dev/null; then
  die "browser dependency check failed"
fi

start_runtime() {
  "$BROWSER_RUNTIME_HELPER" start \
    --run-dir "$run_dir" \
    --profile-dir "$profile_dir" \
    --url "$url" \
    --origin "$origin" \
    --session-key "$session_key" \
    --mode gui >/dev/null
}

select_target() {
  "$BROWSER_RUNTIME_HELPER" select-target \
    --run-dir "$run_dir" \
    --origin "$origin" \
    --target-url "$url"
}

runtime_reused="false"
if "$BROWSER_RUNTIME_HELPER" verify \
  --run-dir "$run_dir" \
  --manifest-root "$manifest_root" \
  --origin "$origin" \
  --session-key "$session_key" >/dev/null 2>&1; then
  runtime_reused="true"
else
  start_runtime
fi

status_output="$("$BROWSER_RUNTIME_HELPER" status --run-dir "$run_dir" --origin "$origin" --session-key "$session_key")"
runtime_status="$(status_field status "$status_output")"
cdp_port="$(status_field cdp_port "$status_output")"
page_status=""
target_id=""
recovery_attempted="false"

evaluate_page_state() {
  local current_target_id="$1"
  local challenge_output challenge_flag login_output login_flag page_info_output page_url
  challenge_output="$("$BROWSER_RUNTIME_HELPER" check-page --run-dir "$run_dir" --target-id "$current_target_id" --check challenge)"
  challenge_flag="$(json_field hasChallenge "$challenge_output")"
  if [ "$challenge_flag" = "true" ]; then
    page_status="challenge"
    return 0
  fi

  login_output="$("$BROWSER_RUNTIME_HELPER" check-page --run-dir "$run_dir" --target-id "$current_target_id" --check login-wall)"
  login_flag="$(json_field hasLoginWall "$login_output")"
  if [ "$login_flag" = "true" ]; then
    page_status="login-wall"
    return 0
  fi

  page_info_output="$("$BROWSER_RUNTIME_HELPER" check-page --run-dir "$run_dir" --target-id "$current_target_id" --check page-info)"
  page_url="$(json_field url "$page_info_output")"
  if [ "$page_url" = "$url" ]; then
    page_status="ready"
    return 0
  fi

  page_status="target-mismatch"
  return 1
}

target_id="$(select_target || true)"
needs_recovery="false"
if [ -n "$target_id" ]; then
  if ! evaluate_page_state "$target_id"; then
    needs_recovery="true"
  fi
else
  page_status="target-mismatch"
  needs_recovery="true"
fi

if [ "$needs_recovery" = "true" ]; then
  recovery_attempted="true"
  if [ "$runtime_status" = "running" ] && [ -n "$target_id" ] && [ -n "$cdp_port" ]; then
    "$PAGE_OPS_HELPER" \
      --port "$cdp_port" \
      --target-id "$target_id" \
      --navigate "$url" \
      --wait-navigation >/dev/null 2>&1 || true
  else
    start_runtime >/dev/null 2>&1 || true
  fi
  status_output="$("$BROWSER_RUNTIME_HELPER" status --run-dir "$run_dir" --origin "$origin" --session-key "$session_key")"
  runtime_status="$(status_field status "$status_output")"
  cdp_port="$(status_field cdp_port "$status_output")"
  target_id="$(select_target || true)"
  if [ "$runtime_status" = "running" ] && [ -n "$target_id" ]; then
    evaluate_page_state "$target_id" || true
  else
    page_status="target-mismatch"
  fi
fi

assisted_session=""
lan_novnc_url=""
PRESERVE_RUNTIME_ON_EXIT="false"
case "$page_status" in
  challenge|login-wall|target-mismatch)
    assist_output="$("$ASSIST_HELPER" start \
      --run-dir "$run_dir" \
      --origin "$origin" \
      --target-url "$url" \
      --session-key "$session_key" \
      --profile-dir "$profile_dir" \
      --manifest-root "$manifest_root")"
    lan_novnc_url="$(status_field lan_novnc_url "$assist_output")"
    [ -n "$lan_novnc_url" ] || die "assisted handoff missing lan_novnc_url"
    assisted_session="true"
    PRESERVE_RUNTIME_ON_EXIT="true"
    ;;
  *)
    ;;
esac

emit_result \
  "$route" \
  "$reason" \
  "$needs_browser" \
  "$origin" \
  "$run_dir" \
  "$profile_dir" \
  "$runtime_status" \
  "$page_status" \
  "$target_id" \
  "$recovery_attempted" \
  "$assisted_session" \
  "$lan_novnc_url"
