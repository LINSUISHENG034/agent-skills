#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/runtime-common.sh"

usage() {
  cat <<'EOF'
Usage:
  open-host-page.sh --url URL [--url URL ...] [--session-key KEY] [--task-mode MODE] [--expected-action ACTION] [--cleanup-on-exit] [--run-dir DIR] [--manifest-root DIR] [--output-dir DIR]

Options:
  --url URL
  --session-key KEY
  --task-mode MODE           latest|article|batch-read|dynamic|protected|interactive|login-required|host-browser
  --expected-action ACTION   search|fetch|extract|browser (legacy lightweight alias accepted)
  --cleanup-on-exit          tear down the browser runtime before the script exits
  --run-dir DIR
  --manifest-root DIR
  --output-dir DIR           save lightweight extraction markdown snapshots
EOF
}

die() {
  local message="$1"
  local error_code="${2:-entrypoint_error}"
  local suggested_action="${3:-inspect-arguments-and-runtime}"
  python3 - "$error_code" "$message" "$suggested_action" <<'PY' >&2
import json
import sys

error_code, message, suggested_action = sys.argv[1:]
print(json.dumps({
    "status": "error",
    "error_code": error_code,
    "message": message,
    "suggested_action": suggested_action,
}))
PY
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
import json
import sys

target = sys.argv[1]
payload = sys.argv[2]

try:
    parsed = json.loads(payload)
except json.JSONDecodeError:
    parsed = None

if isinstance(parsed, dict) and target in parsed:
    value = parsed.get(target)
    if isinstance(value, bool):
        print("true" if value else "false")
    elif isinstance(value, (dict, list)):
        print(json.dumps(value))
    elif value is not None:
        print(value)
    raise SystemExit(0)

for raw in payload.splitlines():
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

urls_match_normalized() {
  local current_url="$1"
  local expected_url="$2"
  python3 - "$current_url" "$expected_url" <<'PY'
import sys
from urllib.parse import urlparse, urlunparse

current_raw, expected_raw = sys.argv[1:]

def normalize(value: str) -> str:
    raw = (value or "").strip()
    if not raw:
        return ""
    parsed = urlparse(raw)
    if not parsed.scheme or not parsed.netloc:
        return raw.rstrip("/")
    path = parsed.path or ""
    if path not in ("", "/"):
        path = path.rstrip("/")
    else:
        path = ""
    return urlunparse((
        parsed.scheme.lower(),
        parsed.netloc.lower(),
        path,
        parsed.params,
        parsed.query,
        "",
    ))

current_value = normalize(current_raw)
expected_value = normalize(expected_raw)
if current_value and expected_value and current_value == expected_value:
    raise SystemExit(0)
raise SystemExit(1)
PY
}

emit_result() {
  python3 - "$@" <<'PY'
import json
import sys

(
    route,
    reason,
    needs_browser,
    origin,
    status,
    next_action,
    operator_required,
    operator_url,
    blocking_reason,
    resume_command,
    message_for_agent,
    run_dir,
    profile_dir,
    runtime_status,
    page_status,
    target_id,
    recovery_attempted,
    assisted_session,
    lan_novnc_url,
) = sys.argv[1:20]

payload = {
    "route": route,
    "reason": reason,
    "needs_browser": needs_browser == "true",
    "origin": origin,
    "status": status,
    "next_action": next_action,
    "operator_required": operator_required == "true",
}

if operator_url:
    payload["operator_url"] = operator_url
if blocking_reason:
    payload["blocking_reason"] = blocking_reason
if resume_command:
    payload["resume_command"] = resume_command
if message_for_agent:
    payload["message_for_agent"] = message_for_agent
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

emit_extract_result() {
  python3 - "$@" <<'PY'
import json
import sys

route, reason, needs_browser, origin, extract_payload = sys.argv[1:6]
content = json.loads(extract_payload)
payload = {
    "route": route,
    "reason": reason,
    "needs_browser": bool(content.get("needs_browser", needs_browser == "true")),
    "needs_browser_reason": content.get("needs_browser_reason", ""),
    "origin": origin,
    "status": "ready",
    "next_action": "none",
    "operator_required": False,
    "content_contract": "markdown-snapshot",
}
for key in (
    "title",
    "url",
    "source_type",
    "content_type",
    "extraction_method",
    "quality",
    "fetched_at",
    "summary",
    "saved_path",
    "error",
):
    if key in content:
        payload[key] = content[key]
if content.get("markdown"):
    payload["markdown"] = content["markdown"]
print(json.dumps(payload, ensure_ascii=False))
PY
}

emit_batch_extract_result() {
  python3 - "$@" <<'PY'
import json
import sys

route, reason, origin, results_raw = sys.argv[1:5]
results = json.loads(results_raw)
needs_browser_items = [item for item in results if item.get("needs_browser")]
payload = {
    "route": route,
    "reason": reason,
    "needs_browser": bool(needs_browser_items),
    "needs_browser_reason": "one-or-more-extractions-need-browser" if needs_browser_items else "",
    "origin": origin,
    "status": "ready",
    "next_action": "none",
    "operator_required": False,
    "content_contract": "batch-markdown-snapshot",
    "results": results,
    "quality_summary": {
        "total": len(results),
        "needs_browser": len(needs_browser_items),
        "high": sum(1 for item in results if item.get("quality") == "high"),
        "medium": sum(1 for item in results if item.get("quality") == "medium"),
        "low": sum(1 for item in results if item.get("quality") == "low"),
    },
}
print(json.dumps(payload, ensure_ascii=False))
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
    search|fetch|extract|browser)
      if [ "$route" != "$expected_action" ]; then
        die "route assertion failed before browser orchestration started: expected route $expected_action but router returned $route" "route_assertion_failed" "change-task-mode-or-expected-action"
      fi
      ;;
    *)
      die "--expected-action must be search, fetch, extract, browser, or legacy lightweight" "invalid_arguments" "use-a-supported-expected-action"
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
CONTENT_EXTRACT_HELPER="${HOST_WEB_ACCESS_EXTRACT_HELPER:-$SCRIPT_DIR/content-extract.py}"
SITE_REGISTRY_HELPER="${HOST_WEB_ACCESS_SITE_REGISTRY_HELPER:-$SCRIPT_DIR/site-session-registry.sh}"

task_mode="latest"
expected_action=""
cleanup_on_exit="false"
url=""
urls=()
session_key="default"
run_dir=""
manifest_root=""
output_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      url="$2"
      urls+=("$2")
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
    --cleanup-on-exit)
      cleanup_on_exit="true"
      shift
      ;;
    --run-dir)
      run_dir="$2"
      shift 2
      ;;
    --manifest-root)
      manifest_root="$2"
      shift 2
      ;;
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1" "invalid_arguments" "run-open-host-page-help"
      ;;
  esac
done

[ "${#urls[@]}" -gt 0 ] || die "--url is required" "invalid_arguments" "provide-url"
url="${urls[0]}"

origin="$(derive_origin "$url")"
base_root="${HOME}/.agent-browser"
manifest_root="${manifest_root:-$base_root}"
run_dir="${run_dir:-$(runtime_scoped_path "$base_root" run "$origin" "$session_key")}"

route_output="$(route_for_mode "$task_mode")"
route="$(json_field route "$route_output")"
reason="$(json_field reason "$route_output")"
needs_browser="$(json_field needs_browser "$route_output")"
assert_expected_route

run_extract() {
  local extract_url="$1"
  local extract_args=(--url "$extract_url")
  if [ -n "$output_dir" ]; then
    extract_args+=(--output-dir "$output_dir")
  fi
  "$CONTENT_EXTRACT_HELPER" "${extract_args[@]}"
}

if [ "$route" != "browser" ]; then
  if [ "$route" = "extract" ]; then
    if [ "${#urls[@]}" -gt 1 ] || [ "$task_mode" = "batch-read" ]; then
      extract_results="[]"
      for current_url in "${urls[@]}"; do
        current_result="$(run_extract "$current_url")"
        extract_results="$(python3 - "$extract_results" "$current_result" <<'PY'
import json
import sys

items = json.loads(sys.argv[1])
items.append(json.loads(sys.argv[2]))
print(json.dumps(items, ensure_ascii=False))
PY
)"
      done
      emit_batch_extract_result "$route" "$reason" "$origin" "$extract_results"
      exit 0
    fi
    extract_output="$(run_extract "$url")"
    emit_extract_result "$route" "$reason" "$needs_browser" "$origin" "$extract_output"
    exit 0
  fi
  emit_result "$route" "$reason" "$needs_browser" "$origin" "ready" "none" "false" "" "" "" "" "" "" "" "" "" "" "" ""
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
[ -n "$profile_dir" ] || die "profile-resolution did not return profile_dir" "profile_resolution_failed" "check-profile-resolution-output"

cleanup_browser() {
  if [ "${PRESERVE_RUNTIME_ON_EXIT:-false}" = "true" ]; then
    return 0
  fi
  "$CLEANUP_HELPER" --run-dir "$run_dir" >/dev/null 2>&1 || true
}

trap cleanup_browser EXIT

if ! "$BROWSER_RUNTIME_HELPER" ensure-browser --run-dir "$run_dir" >/dev/null; then
  die "browser dependency check failed" "browser_dependency_missing" "install-google-chrome-or-chromium"
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
  "$CLEANUP_HELPER" --run-dir "$run_dir" >/dev/null 2>&1 || true
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
  if urls_match_normalized "$page_url" "$url"; then
    page_status="ready"
    return 0
  fi

  page_status="target-mismatch"
  return 1
}

record_reusable_site() {
  "$SITE_REGISTRY_HELPER" write \
    --root "$base_root" \
    --site "$(site_key "$origin")" \
    --session-key "$session_key" \
    --profile-dir "$profile_dir" \
    --source-origin "$origin" >/dev/null 2>&1 || true
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
status="ready"
next_action="none"
operator_required="false"
operator_url=""
blocking_reason=""
resume_command=""
message_for_agent=""
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
    [ -n "$lan_novnc_url" ] || die "assisted handoff missing lan_novnc_url" "assist_handoff_failed" "inspect-assist-lan-session-output"
    assisted_session="true"
    status="needs-user"
    next_action="open-novnc"
    operator_required="true"
    operator_url="${lan_novnc_url}"
    blocking_reason="${page_status}"
    printf -v resume_command '%q capture --run-dir %q --origin %q --target-url %q --session-key %q --profile-dir %q --manifest-root %q' \
      "$ASSIST_HELPER" "$run_dir" "$origin" "$url" "$session_key" "$profile_dir" "$manifest_root"
    message_for_agent="Stop autonomous browsing. Ask the user to open operator_url and complete the required interaction, then run resume_command."
    PRESERVE_RUNTIME_ON_EXIT="true"
    ;;
  *)
    if [ "$page_status" = "ready" ]; then
      record_reusable_site
    fi
    if [ "$cleanup_on_exit" != "true" ]; then
      PRESERVE_RUNTIME_ON_EXIT="true"
    fi
    ;;
esac

emit_result \
  "$route" \
  "$reason" \
  "$needs_browser" \
  "$origin" \
  "$status" \
  "$next_action" \
  "$operator_required" \
  "$operator_url" \
  "$blocking_reason" \
  "$resume_command" \
  "$message_for_agent" \
  "$run_dir" \
  "$profile_dir" \
  "$runtime_status" \
  "$page_status" \
  "$target_id" \
  "$recovery_attempted" \
  "$assisted_session" \
  "$lan_novnc_url"
