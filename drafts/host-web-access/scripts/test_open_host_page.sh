#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

setup_stubs() {
  local tmp="$1"
  mkdir -p "$tmp/bin"

  cat >"$tmp/bin/route-web-task.sh" <<'EOF'
#!/usr/bin/env bash
LOG="${LOG_FILE}"
echo "route:$1" >>"$LOG"
case "$1" in
  --latest) echo '{"route":"search","reason":"latest-info","needs_browser":false}' ;;
  --interactive) echo '{"route":"browser","reason":"interaction-required","needs_browser":true}' ;;
  *) echo '{"route":"browser","reason":"host-browser-requested","needs_browser":true}' ;;
esac
EOF
  chmod +x "$tmp/bin/route-web-task.sh"

  cat >"$tmp/bin/profile-resolution.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${LOG_FILE}"
echo "profile:$*" >>"$LOG"
printf '{"profile_dir":"%s"}\n' "${PROFILE_DIR_RESPONSE}"
EOF
  chmod +x "$tmp/bin/profile-resolution.sh"

  cat >"$tmp/bin/browser-runtime.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${LOG_FILE}"
echo "runtime:$*" >>"$LOG"
STATE_DIR="${RUNTIME_STATE_DIR:-}"
if [ -n "$STATE_DIR" ]; then
  mkdir -p "$STATE_DIR"
fi

next_sequence_value() {
  local name="$1"
  local sequence="${2:-}"
  local index_file="$STATE_DIR/$name.index"
  local index=0
  if [ -f "$index_file" ]; then
    index="$(cat "$index_file" 2>/dev/null || printf '0')"
  fi
  local selected=""
  local current=0
  IFS=',' read -r -a values <<<"$sequence"
  for value in "${values[@]}"; do
    if [ "$current" -eq "$index" ]; then
      selected="$value"
      break
    fi
    current=$((current + 1))
  done
  if [ -z "$selected" ] && [ "${#values[@]}" -gt 0 ]; then
    selected="${values[${#values[@]}-1]}"
  fi
  printf '%s\n' "$((index + 1))" >"$index_file"
  printf '%s\n' "$selected"
}

case "${1:-}" in
  ensure-browser) exit 0 ;;
  start)
    if [ -n "$STATE_DIR" ]; then
      local_count_file="$STATE_DIR/start.count"
      local_count=0
      if [ -f "$local_count_file" ]; then
        local_count="$(cat "$local_count_file" 2>/dev/null || printf '0')"
      fi
      printf '%s\n' "$((local_count + 1))" >"$local_count_file"
    fi
    exit 0
    ;;
  status)
    printf 'status: %s\n' "${RUNTIME_STATUS_RESPONSE:-running}"
    ;;
  verify)
    if [ "${VERIFY_BEHAVIOR:-success}" = "fail" ]; then
      echo "verify failed" >&2
      exit 1
    fi
    printf '{"state":"ready","session_key":"%s"}\n' "${VERIFY_SESSION_KEY:-default}"
    ;;
  select-target)
    selected="$(next_sequence_value select_target "${SELECT_TARGET_SEQUENCE:-}")"
    if [ "$selected" = "__EMPTY__" ]; then
      selected=""
    fi
    printf '%s\n' "$selected"
    ;;
  check-page)
    check_type=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --check)
          check_type="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    case "${PAGE_STATUS_RESPONSE:-ready}:$check_type" in
      challenge:challenge)
        printf '{"hasChallenge": true, "indicators": ["turnstile"]}\n'
        ;;
      login-wall:login-wall)
        printf '{"hasLoginWall": true, "loginHits": ["Sign in"]}\n'
        ;;
      *:challenge)
        printf '{"hasChallenge": false, "indicators": []}\n'
        ;;
      *:login-wall)
        printf '{"hasLoginWall": false, "loginHits": []}\n'
        ;;
      *:page-info)
        printf '{"title": "Page", "url": "%s"}\n' "${PAGE_INFO_URL_RESPONSE:-https://protected.example/dashboard}"
        ;;
      *)
        printf '{}\n'
        ;;
    esac
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/browser-runtime.sh"

  cat >"$tmp/bin/assist-lan-session.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${LOG_FILE}"
echo "assist:$*" >>"$LOG"
case "${1:-}" in
  start)
    printf 'lan_novnc_url: %s\n' "${ASSIST_LAN_URL_RESPONSE:-http://192.168.1.44:6084/vnc.html?autoconnect=1&resize=remote}"
    ;;
esac
exit 0
EOF
  chmod +x "$tmp/bin/assist-lan-session.sh"

  cat >"$tmp/bin/cleanup-host-runtime.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${LOG_FILE}"
echo "cleanup:$*" >>"$LOG"
exit 0
EOF
  chmod +x "$tmp/bin/cleanup-host-runtime.sh"
}

assert_json_value() {
  local payload="$1"
  local field="$2"
  local expected="$3"
  python3 - "$payload" "$field" "$expected" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
field = sys.argv[2]
expected = sys.argv[3]
actual = data.get(field)
if isinstance(actual, bool):
    actual = "true" if actual else "false"
assert actual == expected, data
PY
}

assert_json_has_fields() {
  local payload="$1"
  shift
  python3 - "$payload" "$@" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
for field in sys.argv[2:]:
    assert field in data, data
PY
}

assert_json_missing_field() {
  local payload="$1"
  local field="$2"
  python3 - "$payload" "$field" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
assert sys.argv[2] not in data, data
PY
}

assert_start_count() {
  local tmp="$1"
  local expected="$2"
  local count_file="$tmp/runtime-state/start.count"
  local actual="0"
  if [ -f "$count_file" ]; then
    actual="$(cat "$count_file")"
  fi
  [ "$actual" = "$expected" ]
}

run_lightweight() {
  local tmp="$1"
  local output
  setup_stubs "$tmp"
  output="$(
    LOG_FILE="$tmp/actions.log" \
    PROFILE_DIR_RESPONSE="$tmp/resolved-profile" \
    HOST_WEB_ACCESS_ROUTE_HELPER="$tmp/bin/route-web-task.sh" \
    HOST_WEB_ACCESS_PROFILE_HELPER="$tmp/bin/profile-resolution.sh" \
    HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER="$tmp/bin/browser-runtime.sh" \
    HOST_WEB_ACCESS_ASSIST_HELPER="$tmp/bin/assist-lan-session.sh" \
    HOST_WEB_ACCESS_CLEANUP_HELPER="$tmp/bin/cleanup-host-runtime.sh" \
      bash "$BASE_DIR/open-host-page.sh" \
      --url "https://public.example/article" \
      --task-mode latest \
      --expected-action search
  )"
  assert_json_has_fields "$output" route reason needs_browser origin
  assert_json_value "$output" route search
  assert_json_value "$output" reason latest-info
  assert_json_value "$output" needs_browser false
  assert_json_value "$output" origin https://public.example
  assert_json_missing_field "$output" run_dir
  grep -q 'route:--latest' "$tmp/actions.log"
  ! grep -q '^profile:' "$tmp/actions.log"
  ! grep -q '^runtime:' "$tmp/actions.log"
}

run_expected_action_failure() {
  local tmp="$1"
  local output status
  setup_stubs "$tmp"
  set +e
  output="$(
    LOG_FILE="$tmp/actions.log" \
    PROFILE_DIR_RESPONSE="$tmp/resolved-profile" \
    HOST_WEB_ACCESS_ROUTE_HELPER="$tmp/bin/route-web-task.sh" \
    HOST_WEB_ACCESS_PROFILE_HELPER="$tmp/bin/profile-resolution.sh" \
    HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER="$tmp/bin/browser-runtime.sh" \
    HOST_WEB_ACCESS_ASSIST_HELPER="$tmp/bin/assist-lan-session.sh" \
    HOST_WEB_ACCESS_CLEANUP_HELPER="$tmp/bin/cleanup-host-runtime.sh" \
      bash "$BASE_DIR/open-host-page.sh" \
      --url "https://public.example/article" \
      --task-mode latest \
      --expected-action browser 2>&1
  )"
  status=$?
  set -e

  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'route assertion failed before browser orchestration started'
  ! grep -q '^profile:' "$tmp/actions.log"
  ! grep -q '^runtime:' "$tmp/actions.log"
}

run_browser_path() {
  local tmp="$1"
  local output
  setup_stubs "$tmp"
  output="$(
    LOG_FILE="$tmp/actions.log" \
    PROFILE_DIR_RESPONSE="$tmp/resolved-profile" \
    RUNTIME_STATUS_RESPONSE=running \
    VERIFY_BEHAVIOR=success \
    SELECT_TARGET_SEQUENCE=page-dashboard \
    PAGE_STATUS_RESPONSE=ready \
    PAGE_INFO_URL_RESPONSE="https://protected.example/dashboard" \
    RUNTIME_STATE_DIR="$tmp/runtime-state" \
    HOST_WEB_ACCESS_ROUTE_HELPER="$tmp/bin/route-web-task.sh" \
    HOST_WEB_ACCESS_PROFILE_HELPER="$tmp/bin/profile-resolution.sh" \
    HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER="$tmp/bin/browser-runtime.sh" \
    HOST_WEB_ACCESS_ASSIST_HELPER="$tmp/bin/assist-lan-session.sh" \
    HOST_WEB_ACCESS_CLEANUP_HELPER="$tmp/bin/cleanup-host-runtime.sh" \
      bash "$BASE_DIR/open-host-page.sh" \
      --url "https://protected.example/dashboard" \
      --task-mode interactive \
      --expected-action browser \
      --session-key foxcode-main \
      --run-dir "$tmp/browser-run"
  )"

  assert_json_has_fields "$output" route reason needs_browser origin run_dir profile_dir runtime_status page_status target_id recovery_attempted
  assert_json_value "$output" route browser
  assert_json_value "$output" reason interaction-required
  assert_json_value "$output" needs_browser true
  assert_json_value "$output" origin https://protected.example
  assert_json_value "$output" run_dir "$tmp/browser-run"
  assert_json_value "$output" profile_dir "$tmp/resolved-profile"
  assert_json_value "$output" runtime_status running
  assert_json_value "$output" page_status ready
  assert_json_value "$output" target_id page-dashboard
  assert_json_value "$output" recovery_attempted false
  assert_json_missing_field "$output" lan_novnc_url
  grep -q 'route:--interactive' "$tmp/actions.log"
  grep -q 'profile:resolve --root ' "$tmp/actions.log"
  grep -q -- '--origin https://protected.example' "$tmp/actions.log"
  grep -q -- '--session-key foxcode-main' "$tmp/actions.log"
  grep -q 'runtime:ensure-browser' "$tmp/actions.log"
  grep -q 'runtime:verify .*--session-key foxcode-main' "$tmp/actions.log"
  ! grep -q '^runtime:start ' "$tmp/actions.log"
  grep -q 'runtime:select-target .*--target-url https://protected.example/dashboard' "$tmp/actions.log"
  grep -q 'runtime:check-page .*--check challenge' "$tmp/actions.log"
  grep -q 'runtime:check-page .*--check login-wall' "$tmp/actions.log"
  grep -q 'runtime:check-page .*--check page-info' "$tmp/actions.log"
  grep -q 'cleanup:--run-dir ' "$tmp/actions.log"
  ! grep -q '^assist:' "$tmp/actions.log"
}

run_assist_path_challenge() {
  local tmp="$1"
  local output
  setup_stubs "$tmp"
  output="$(
    LOG_FILE="$tmp/actions.log" \
    PROFILE_DIR_RESPONSE="$tmp/resolved-profile" \
    RUNTIME_STATUS_RESPONSE=running \
    VERIFY_BEHAVIOR=success \
    SELECT_TARGET_SEQUENCE=page-login \
    PAGE_STATUS_RESPONSE=challenge \
    RUNTIME_STATE_DIR="$tmp/runtime-state" \
    ASSIST_LAN_URL_RESPONSE="http://192.168.1.77:6084/vnc.html?autoconnect=1&resize=remote" \
    HOST_WEB_ACCESS_ROUTE_HELPER="$tmp/bin/route-web-task.sh" \
    HOST_WEB_ACCESS_PROFILE_HELPER="$tmp/bin/profile-resolution.sh" \
    HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER="$tmp/bin/browser-runtime.sh" \
    HOST_WEB_ACCESS_ASSIST_HELPER="$tmp/bin/assist-lan-session.sh" \
    HOST_WEB_ACCESS_CLEANUP_HELPER="$tmp/bin/cleanup-host-runtime.sh" \
      bash "$BASE_DIR/open-host-page.sh" \
      --url "https://protected.example/dashboard" \
      --task-mode interactive \
      --expected-action browser \
      --run-dir "$tmp/assist-run"
  )"

  assert_json_has_fields "$output" route reason needs_browser origin run_dir profile_dir runtime_status page_status target_id recovery_attempted assisted_session lan_novnc_url
  assert_json_value "$output" runtime_status running
  assert_json_value "$output" page_status challenge
  assert_json_value "$output" target_id page-login
  assert_json_value "$output" recovery_attempted false
  assert_json_value "$output" assisted_session true
  assert_json_value "$output" lan_novnc_url "http://192.168.1.77:6084/vnc.html?autoconnect=1&resize=remote"
  grep -q '^assist:start ' "$tmp/actions.log"
  grep -q '^assist:capture ' "$tmp/actions.log"
  grep -q '^assist:stop ' "$tmp/actions.log"
}

run_assist_path_login_wall() {
  local tmp="$1"
  local output
  setup_stubs "$tmp"
  output="$(
    LOG_FILE="$tmp/actions.log" \
    PROFILE_DIR_RESPONSE="$tmp/resolved-profile" \
    RUNTIME_STATUS_RESPONSE=running \
    VERIFY_BEHAVIOR=success \
    SELECT_TARGET_SEQUENCE=page-login \
    PAGE_STATUS_RESPONSE=login-wall \
    RUNTIME_STATE_DIR="$tmp/runtime-state" \
    ASSIST_LAN_URL_RESPONSE="http://192.168.1.55:6084/vnc.html?autoconnect=1&resize=remote" \
    HOST_WEB_ACCESS_ROUTE_HELPER="$tmp/bin/route-web-task.sh" \
    HOST_WEB_ACCESS_PROFILE_HELPER="$tmp/bin/profile-resolution.sh" \
    HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER="$tmp/bin/browser-runtime.sh" \
    HOST_WEB_ACCESS_ASSIST_HELPER="$tmp/bin/assist-lan-session.sh" \
    HOST_WEB_ACCESS_CLEANUP_HELPER="$tmp/bin/cleanup-host-runtime.sh" \
      bash "$BASE_DIR/open-host-page.sh" \
      --url "https://protected.example/dashboard" \
      --task-mode interactive \
      --expected-action browser \
      --run-dir "$tmp/assist-login-run"
  )"

  assert_json_has_fields "$output" route reason needs_browser origin run_dir profile_dir runtime_status page_status target_id recovery_attempted assisted_session lan_novnc_url
  assert_json_value "$output" runtime_status running
  assert_json_value "$output" page_status login-wall
  assert_json_value "$output" target_id page-login
  assert_json_value "$output" recovery_attempted false
  assert_json_value "$output" assisted_session true
  assert_json_value "$output" lan_novnc_url "http://192.168.1.55:6084/vnc.html?autoconnect=1&resize=remote"
  grep -q '^assist:start ' "$tmp/actions.log"
  grep -q '^assist:capture ' "$tmp/actions.log"
  grep -q '^assist:stop ' "$tmp/actions.log"
}

run_wrong_page_recovery_success() {
  local tmp="$1"
  local output
  setup_stubs "$tmp"
  output="$(
    LOG_FILE="$tmp/actions.log" \
    PROFILE_DIR_RESPONSE="$tmp/resolved-profile" \
    RUNTIME_STATUS_RESPONSE=running \
    VERIFY_BEHAVIOR=success \
    SELECT_TARGET_SEQUENCE="__EMPTY__,page-dashboard" \
    PAGE_STATUS_RESPONSE=ready \
    PAGE_INFO_URL_RESPONSE="https://protected.example/dashboard" \
    RUNTIME_STATE_DIR="$tmp/runtime-state" \
    HOST_WEB_ACCESS_ROUTE_HELPER="$tmp/bin/route-web-task.sh" \
    HOST_WEB_ACCESS_PROFILE_HELPER="$tmp/bin/profile-resolution.sh" \
    HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER="$tmp/bin/browser-runtime.sh" \
    HOST_WEB_ACCESS_ASSIST_HELPER="$tmp/bin/assist-lan-session.sh" \
    HOST_WEB_ACCESS_CLEANUP_HELPER="$tmp/bin/cleanup-host-runtime.sh" \
      bash "$BASE_DIR/open-host-page.sh" \
      --url "https://protected.example/dashboard" \
      --task-mode interactive \
      --expected-action browser \
      --run-dir "$tmp/recovery-run"
  )"

  assert_json_has_fields "$output" page_status recovery_attempted target_id
  assert_json_value "$output" page_status ready
  assert_json_value "$output" recovery_attempted true
  assert_json_value "$output" target_id page-dashboard
  ! grep -q '^assist:' "$tmp/actions.log"
  assert_start_count "$tmp" 1
}

run_wrong_page_recovery_assisted() {
  local tmp="$1"
  local output
  setup_stubs "$tmp"
  output="$(
    LOG_FILE="$tmp/actions.log" \
    PROFILE_DIR_RESPONSE="$tmp/resolved-profile" \
    RUNTIME_STATUS_RESPONSE=running \
    VERIFY_BEHAVIOR=success \
    SELECT_TARGET_SEQUENCE="__EMPTY__,__EMPTY__" \
    PAGE_STATUS_RESPONSE=ready \
    RUNTIME_STATE_DIR="$tmp/runtime-state" \
    ASSIST_LAN_URL_RESPONSE="http://192.168.1.99:6084/vnc.html?autoconnect=1&resize=remote" \
    HOST_WEB_ACCESS_ROUTE_HELPER="$tmp/bin/route-web-task.sh" \
    HOST_WEB_ACCESS_PROFILE_HELPER="$tmp/bin/profile-resolution.sh" \
    HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER="$tmp/bin/browser-runtime.sh" \
    HOST_WEB_ACCESS_ASSIST_HELPER="$tmp/bin/assist-lan-session.sh" \
    HOST_WEB_ACCESS_CLEANUP_HELPER="$tmp/bin/cleanup-host-runtime.sh" \
      bash "$BASE_DIR/open-host-page.sh" \
      --url "https://protected.example/dashboard" \
      --task-mode interactive \
      --expected-action browser \
      --run-dir "$tmp/recovery-assist-run"
  )"

  assert_json_has_fields "$output" page_status recovery_attempted assisted_session lan_novnc_url
  assert_json_value "$output" page_status target-mismatch
  assert_json_value "$output" recovery_attempted true
  assert_json_missing_field "$output" target_id
  assert_json_value "$output" assisted_session true
  assert_json_value "$output" lan_novnc_url "http://192.168.1.99:6084/vnc.html?autoconnect=1&resize=remote"
  assert_start_count "$tmp" 1
  grep -q '^assist:start ' "$tmp/actions.log"
}

run_expected_failure() {
  set +e
  bash "$BASE_DIR/open-host-page.sh" >/dev/null 2>&1
  local status=$?
  set -e
  [ "$status" -ne 0 ]
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_expected_failure
run_lightweight "$TMP_DIR/light"
run_expected_action_failure "$TMP_DIR/route-assert"
run_browser_path "$TMP_DIR/browser"
run_assist_path_challenge "$TMP_DIR/assist-challenge"
run_assist_path_login_wall "$TMP_DIR/assist-login-wall"
run_wrong_page_recovery_success "$TMP_DIR/recovery-success"
run_wrong_page_recovery_assisted "$TMP_DIR/recovery-assist"
