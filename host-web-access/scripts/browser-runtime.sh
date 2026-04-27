#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/runtime-common.sh"

usage() {
  cat <<'EOF'
Usage:
  browser-runtime.sh start --url URL [options]
  browser-runtime.sh status [options]
  browser-runtime.sh stop [options]
  browser-runtime.sh list-targets [options]
  browser-runtime.sh check-page --check TYPE [options]
  browser-runtime.sh select-target [--origin URL] [--target-url URL] [--targets-json JSON]
  browser-runtime.sh verify --origin URL --session-key KEY [--manifest-root DIR]
  browser-runtime.sh doctor [--repair] [options]
  browser-runtime.sh ensure-browser [options]

Options:
  --browser CMD
  --cdp-port PORT
  --check TYPE
  --display NUM
  --manifest-root DIR
  --mode headless|gui
  --origin URL
  --profile-dir DIR
  --run-dir DIR
  --session-key KEY
  --target-id ID
  --target-url URL
  --targets-json JSON
  --url URL
EOF
}

die() {
  local message="$1"
  local error_code="${2:-runtime_error}"
  local suggested_action="${3:-run-browser-runtime-doctor}"
  python3 - "$error_code" "$message" "$suggested_action" <<'PY' >&2
import json
import sys

error_code, message, suggested_action = sys.argv[1:]
print(json.dumps({
    "status": "error",
    "component": "browser-runtime",
    "error_code": error_code,
    "message": message,
    "suggested_action": suggested_action,
}))
PY
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_arg() {
  local name="$1"
  local value="$2"
  [ -n "$value" ] || die "missing required argument: $name"
}

pid_file() {
  printf '%s/%s.pid\n' "$RUN_DIR" "$1"
}

read_pid() {
  local file
  file="$(pid_file "$1")"
  if [ -f "$file" ]; then
    cat "$file"
  fi
}

pid_running() {
  local pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

manifest_helper() {
  "${AGENT_BROWSER_MANIFEST_HELPER:-$SCRIPT_DIR/session-manifest.sh}" "$@"
}

cdp_eval() {
  "${AGENT_BROWSER_CDP_EVAL:-$SCRIPT_DIR/host-page-ops.py}" "$@"
}

cleanup_profile_locks() {
  local profile_dir="$1"
  [ -n "$profile_dir" ] || return 0
  local lock="$profile_dir/SingletonLock"
  if [ -L "$lock" ]; then
    local target pid
    target="$(readlink "$lock" 2>/dev/null || true)"
    pid="${target##*-}"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  rm -f \
    "$lock" \
    "$profile_dir/SingletonSocket" \
    "$profile_dir/SingletonCookie"
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    STATE_PRESENT=1
  else
    STATE_PRESENT=0
  fi
}

write_state() {
  mkdir -p "$RUN_DIR" "$LOG_DIR"
  cat >"$STATE_FILE" <<EOF
MODE=$(printf '%q' "$MODE")
ORIGIN=$(printf '%q' "$ORIGIN")
SESSION_KEY=$(printf '%q' "$SESSION_KEY")
INITIAL_URL=$(printf '%q' "$INITIAL_URL")
PROFILE_DIR=$(printf '%q' "$PROFILE_DIR")
RUN_DIR=$(printf '%q' "$RUN_DIR")
LOG_DIR=$(printf '%q' "$LOG_DIR")
CDP_HOST=$(printf '%q' "$CDP_HOST")
CDP_PORT=$(printf '%q' "$CDP_PORT")
DISPLAY_NUM=$(printf '%q' "$DISPLAY_NUM")
BROWSER_CMD=$(printf '%q' "$BROWSER_CMD")
BROWSER_COMMAND=$(printf '%q' "$BROWSER_COMMAND")
BROWSER_PID=$(printf '%q' "$BROWSER_PID")
STATE=$(printf '%q' "$STATE")
EOF
}

resolve_browser_binary() {
  local candidate="${1:-}"
  if [ -z "$candidate" ]; then
    return 1
  fi
  if [[ "$candidate" == */* ]]; then
    [ -x "$candidate" ] || die "missing browser executable: $candidate"
    printf '%s\n' "$candidate"
    return 0
  fi
  if command -v "$candidate" >/dev/null 2>&1; then
    command -v "$candidate"
    return 0
  fi
  die "missing browser executable: $candidate"
}

detect_browser() {
  local candidate
  if [ -n "${BROWSER_CMD:-}" ]; then
    resolve_browser_binary "$BROWSER_CMD"
    return 0
  fi
  for candidate in google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

start_process() {
  local name="$1"
  local logfile="$2"
  shift 2

  mkdir -p "$RUN_DIR" "$LOG_DIR"
  : >"$logfile"
  setsid "$@" >>"$logfile" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >"$(pid_file "$name")"
  sleep 1
  pid_running "$pid" || die "$name failed to start; inspect $logfile"
  printf '%s\n' "$pid"
}

wait_for_display() {
  local socket_dir="${AGENT_BROWSER_X11_SOCKET_DIR:-/tmp/.X11-unix}"
  local socket="${socket_dir}/X${DISPLAY_NUM}"
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if [ -e "$socket" ]; then
      if ! have_cmd xdpyinfo || DISPLAY=":$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done

  die "Xvfb did not become ready on :$DISPLAY_NUM"
}

cdp_version_ready() {
  python3 - "$CDP_HOST" "$CDP_PORT" <<'PY'
import json
import sys
import urllib.request

host, port = sys.argv[1:]
try:
    with urllib.request.urlopen(f"http://{host}:{port}/json/version", timeout=1.5) as response:
        payload = json.loads(response.read().decode("utf-8"))
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if isinstance(payload, dict) and payload.get("Browser") else 1)
PY
}

wait_for_cdp() {
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if cdp_version_ready; then
      return 0
    fi
    sleep 1
  done

  printf 'CDP did not become ready on %s:%s\n' "$CDP_HOST" "$CDP_PORT" >&2
  return 1
}

resolve_context() {
  BASE_ROOT="${HOME}/.agent-browser"
  MANIFEST_ROOT="${MANIFEST_ROOT:-$BASE_ROOT}"
  SESSION_KEY="${SESSION_KEY:-default}"
  MODE="${CLI_MODE:-${MODE:-headless}}"
  ORIGIN="${CLI_ORIGIN:-${ORIGIN:-}}"
  INITIAL_URL="${CLI_INITIAL_URL:-${INITIAL_URL:-}}"
  BROWSER_CMD="${CLI_BROWSER_CMD:-${BROWSER_CMD:-}}"
  CDP_HOST="${CDP_HOST:-127.0.0.1}"
  CDP_PORT="${CLI_CDP_PORT:-${CDP_PORT:-${HOST_WEB_ACCESS_CDP_PORT:-9222}}}"
  DISPLAY_NUM="${CLI_DISPLAY_NUM:-${DISPLAY_NUM:-${HOST_WEB_ACCESS_DISPLAY_NUM:-88}}}"

  if [ -z "$ORIGIN" ] && [ -n "$INITIAL_URL" ]; then
    ORIGIN="$(derive_origin "$INITIAL_URL")"
  fi
  if [ -z "$ORIGIN" ]; then
    ORIGIN="https://example.com"
  fi
  if [ -z "$INITIAL_URL" ]; then
    INITIAL_URL="$ORIGIN"
  fi

  if [ -n "${CLI_RUN_DIR:-}" ]; then
    RUN_DIR="$CLI_RUN_DIR"
  elif [ -z "${RUN_DIR:-}" ]; then
    RUN_DIR="$(runtime_scoped_path "$BASE_ROOT" run "$ORIGIN" "$SESSION_KEY")"
  fi

  STATE_FILE="$RUN_DIR/runtime.env"
  load_state

  MODE="${CLI_MODE:-${MODE:-headless}}"
  ORIGIN="${CLI_ORIGIN:-${ORIGIN:-$ORIGIN}}"
  INITIAL_URL="${CLI_INITIAL_URL:-${INITIAL_URL:-$ORIGIN}}"
  MANIFEST_ROOT="${CLI_MANIFEST_ROOT:-${MANIFEST_ROOT:-$BASE_ROOT}}"
  SESSION_KEY="${CLI_SESSION_KEY:-${SESSION_KEY:-default}}"
  CDP_HOST="${CDP_HOST:-127.0.0.1}"
  CDP_PORT="${CLI_CDP_PORT:-${CDP_PORT:-${HOST_WEB_ACCESS_CDP_PORT:-9222}}}"
  DISPLAY_NUM="${CLI_DISPLAY_NUM:-${DISPLAY_NUM:-${HOST_WEB_ACCESS_DISPLAY_NUM:-88}}}"
  BROWSER_CMD="${CLI_BROWSER_CMD:-${BROWSER_CMD:-}}"
  LOG_DIR="${LOG_DIR:-$(runtime_scoped_path "$BASE_ROOT" logs "$ORIGIN" "$SESSION_KEY")}"
  PROFILE_DIR="${CLI_PROFILE_DIR:-${PROFILE_DIR:-$(runtime_scoped_path "$BASE_ROOT" profiles "$ORIGIN" "$SESSION_KEY")}}"
  BROWSER_COMMAND="${BROWSER_COMMAND:-}"
  BROWSER_PID="${BROWSER_PID:-}"
  if [ "$STATE_PRESENT" -eq 0 ]; then
    STATE="missing"
  else
    STATE="${STATE:-stopped}"
  fi
}

runtime_status() {
  local browser_pid
  browser_pid="$(read_pid browser || true)"
  if [ -n "$browser_pid" ]; then
    BROWSER_PID="$browser_pid"
  fi

  if pid_running "${BROWSER_PID:-}"; then
    STATE="running"
  elif [ "$STATE_PRESENT" -eq 0 ]; then
    STATE="missing"
  elif [ "${STATE:-}" = "closed" ]; then
    STATE="closed"
  else
    STATE="stopped"
  fi
}

manifest_field() {
  local field="$1"
  local payload="$2"
  python3 - "$field" "$payload" <<'PY'
import json
import sys

field = sys.argv[1]
payload = json.loads(sys.argv[2])
value = payload.get(field)
if value is None:
    raise SystemExit(1)
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

select_target_from_json() {
  local payload="$1"
  python3 - "$ORIGIN" "$TARGET_URL" "$payload" <<'PY'
import json
import sys
from urllib.parse import urlparse

origin, target_url, payload = sys.argv[1:]
targets = [target for target in json.loads(payload or "[]") if target.get("type") == "page"]

def normalized_origin(value: str) -> str:
    parsed = urlparse(value or "")
    if not parsed.scheme or not parsed.netloc:
        return ""
    return f"{parsed.scheme.lower()}://{parsed.netloc.lower()}"

def host(value: str) -> str:
    parsed = urlparse(value or "")
    return parsed.netloc.lower()

origin_norm = normalized_origin(origin)

def score(target):
    url = target.get("url", "")
    url_origin_norm = normalized_origin(url)
    if target_url and url == target_url:
        return (0, url)
    if origin_norm and url_origin_norm == origin_norm:
        return (1, url)
    if origin_norm and host(url) and host(url) == host(origin_norm):
        return (2, url)
    return (9, url)

if targets:
    best = sorted(targets, key=score)[0]
    best_score = score(best)[0]
    if best_score < 9:
        print(best.get("id", ""))
PY
}

load_manifest() {
  manifest_helper show --root "$MANIFEST_ROOT" --origin "$ORIGIN" --session-key "$SESSION_KEY"
}

cmd_status() {
  resolve_context
  runtime_status
  cat <<EOF
status: $STATE
mode: $MODE
url: $INITIAL_URL
origin: $ORIGIN
session_key: $SESSION_KEY
run_dir: $RUN_DIR
profile_dir: $PROFILE_DIR
cdp_host: $CDP_HOST
cdp_port: $CDP_PORT
display: :$DISPLAY_NUM
browser_pid: ${BROWSER_PID:-}
browser_command: ${BROWSER_COMMAND:-}
EOF
}

cmd_ensure_browser() {
  resolve_context
  if ! BROWSER_CMD="$(detect_browser)"; then
    die "missing browser dependency: google-chrome/chromium"
  fi
  printf '%s\n' "$BROWSER_CMD"
}

cmd_check_page() {
  resolve_context
  require_arg --check "$CHECK_TYPE"
  require_arg --cdp-port "$CDP_PORT"
  cdp_eval --port "$CDP_PORT" ${TARGET_ID:+--target-id "$TARGET_ID"} --check "$CHECK_TYPE"
}

cmd_list_targets() {
  resolve_context
  runtime_status
  if [ "$STATE" != "running" ]; then
    printf '[]\n'
    return 0
  fi
  python3 - "$CDP_HOST" "$CDP_PORT" <<'PY'
import json
import sys
import urllib.request

host, port = sys.argv[1:]
try:
    with urllib.request.urlopen(f"http://{host}:{port}/json/list", timeout=2) as response:
        payload = json.loads(response.read().decode("utf-8"))
except Exception:
    print("[]")
    raise SystemExit(0)
print(json.dumps(payload))
PY
}

cmd_select_target() {
  resolve_context
  if [ -z "$TARGETS_JSON" ]; then
    TARGETS_JSON="$(cmd_list_targets)"
  fi
  select_target_from_json "$TARGETS_JSON"
}

cmd_verify() {
  resolve_context
  require_arg --origin "$ORIGIN"
  require_arg --session-key "$SESSION_KEY"

  local manifest browser_pid cdp_port target_id
  manifest="$(load_manifest)" || exit $?
  browser_pid="$(manifest_field browser_pid "$manifest" || true)"
  cdp_port="$(manifest_field cdp_port "$manifest" || true)"
  target_id="$(manifest_field target_id "$manifest" || true)"

  if [ -z "$browser_pid" ] || ! pid_running "$browser_pid"; then
    manifest_helper mark-stale --root "$MANIFEST_ROOT" --origin "$ORIGIN" --session-key "$SESSION_KEY" --reason "browser process is not running" >/dev/null || true
    die "browser is not running for manifest $SESSION_KEY"
  fi

  if [ -n "$cdp_port" ]; then
    if ! python3 - "$cdp_port" <<'PY'
import json
import sys
import urllib.request

port = sys.argv[1]
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=2) as response:
        payload = json.loads(response.read().decode("utf-8"))
except Exception:
    raise SystemExit(1)
if not isinstance(payload, dict) or not payload.get("Browser"):
    raise SystemExit(1)
PY
    then
      manifest_helper mark-stale --root "$MANIFEST_ROOT" --origin "$ORIGIN" --session-key "$SESSION_KEY" --reason "CDP endpoint is unreachable" >/dev/null || true
      die "CDP endpoint is unreachable for manifest $SESSION_KEY"
    fi
    if [ -n "$target_id" ]; then
      if ! python3 - "$cdp_port" "$target_id" <<'PY'
import json
import sys
import urllib.request

port, target_id = sys.argv[1], sys.argv[2]
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=2) as response:
        payload = json.loads(response.read().decode("utf-8"))
except Exception:
    raise SystemExit(1)
targets = payload if isinstance(payload, list) else []
if not any(str(item.get("id", "")) == target_id for item in targets):
    raise SystemExit(1)
PY
      then
        manifest_helper mark-stale --root "$MANIFEST_ROOT" --origin "$ORIGIN" --session-key "$SESSION_KEY" --reason "target_id is no longer present" >/dev/null || true
        die "target_id is no longer present for manifest $SESSION_KEY"
      fi
    fi
  fi

  printf '%s\n' "$manifest"
}

cmd_doctor() {
  resolve_context
  runtime_status

  local issues=()
  local repaired=false
  if [ "$STATE" != "running" ]; then
    issues+=("runtime_not_running")
  elif ! cdp_version_ready; then
    issues+=("cdp_unreachable")
  else
    local targets_json
    targets_json="$(cmd_list_targets)"
    if ! python3 - "$targets_json" <<'PY'
import json
import sys

targets = json.loads(sys.argv[1] or "[]")
raise SystemExit(0 if any(item.get("type") == "page" for item in targets) else 1)
PY
    then
      issues+=("target_missing")
    fi
  fi

  if "$REPAIR" && [ "${#issues[@]}" -gt 0 ]; then
    cleanup_runtime_on_failure
    manifest_helper mark-stale --root "$MANIFEST_ROOT" --origin "$ORIGIN" --session-key "$SESSION_KEY" --reason "doctor detected: ${issues[*]}" >/dev/null 2>&1 || true
    repaired=true
  fi

  python3 - "$STATE" "$RUN_DIR" "$ORIGIN" "$SESSION_KEY" "$CDP_HOST" "$CDP_PORT" "$repaired" "${issues[@]}" <<'PY'
import json
import sys

state, run_dir, origin, session_key, cdp_host, cdp_port, repaired, *issues = sys.argv[1:]
status = "healthy" if not issues else ("stale" if "runtime_not_running" in issues else "broken")
print(json.dumps({
    "status": status,
    "runtime_status": state,
    "run_dir": run_dir,
    "origin": origin,
    "session_key": session_key,
    "cdp_host": cdp_host,
    "cdp_port": int(cdp_port),
    "issues": issues,
    "repaired": repaired == "true",
    "suggested_action": "none" if not issues else ("restart-runtime" if not (repaired == "true") else "retry"),
}, sort_keys=True))
PY
}

cleanup_runtime_on_failure() {
  "$SCRIPT_DIR/cleanup-host-runtime.sh" --run-dir "$RUN_DIR" >/dev/null 2>&1 || true
}

cmd_start() {
  resolve_context
  require_arg --url "$INITIAL_URL"

  case "$MODE" in
    headless|gui) ;;
    *)
      die "--mode must be headless or gui"
      ;;
  esac

  if ! BROWSER_CMD="$(detect_browser)"; then
    die "missing browser dependency: google-chrome/chromium"
  fi
  if [ "$MODE" = "gui" ] && ! have_cmd Xvfb; then
    die "missing dependency: Xvfb"
  fi

  runtime_status
  [ "$STATE" != "running" ] || die "browser runtime already running"

  if [ -z "${CLI_CDP_PORT:-}" ]; then
    CDP_PORT="$(pick_free_tcp_port "$CDP_PORT")" || die "unable to find free CDP port near $CDP_PORT"
  fi
  if [ "$MODE" = "gui" ] && [ -z "${CLI_DISPLAY_NUM:-}" ]; then
    DISPLAY_NUM="$(pick_free_display "$DISPLAY_NUM")" || die "unable to find free display near :$DISPLAY_NUM"
  fi

  mkdir -p "$RUN_DIR" "$LOG_DIR" "$PROFILE_DIR"
  cleanup_profile_locks "$PROFILE_DIR"

  local browser_args=(
    --no-first-run
    --no-default-browser-check
    --user-data-dir="$PROFILE_DIR"
    --remote-debugging-address="$CDP_HOST"
    --remote-debugging-port="$CDP_PORT"
  )

  if [ "$MODE" = "gui" ]; then
    start_process xvfb "$LOG_DIR/xvfb.log" \
      Xvfb ":$DISPLAY_NUM" -screen 0 1600x900x24 -ac +extension RANDR >/dev/null
    wait_for_display
    browser_args+=(--disable-gpu --enable-unsafe-swiftshader --new-window "$INITIAL_URL")
    BROWSER_COMMAND="$(printf '%q ' env DISPLAY=":$DISPLAY_NUM" "$BROWSER_CMD" "${browser_args[@]}")"
    BROWSER_COMMAND="${BROWSER_COMMAND% }"
    BROWSER_PID="$(
      start_process browser "$LOG_DIR/browser.log" \
        env DISPLAY=":$DISPLAY_NUM" \
        "$BROWSER_CMD" \
        "${browser_args[@]}"
    )"
  else
    browser_args=(--headless=new --disable-gpu "${browser_args[@]}" "$INITIAL_URL")
    BROWSER_COMMAND="$(printf '%q ' "$BROWSER_CMD" "${browser_args[@]}")"
    BROWSER_COMMAND="${BROWSER_COMMAND% }"
    BROWSER_PID="$(
      start_process browser "$LOG_DIR/browser.log" \
        "$BROWSER_CMD" \
        "${browser_args[@]}"
    )"
  fi

  STATE="starting"
  write_state
  if ! wait_for_cdp; then
    cleanup_runtime_on_failure
    die "browser runtime failed to expose CDP" "cdp_unreachable" "restart-runtime-or-run-doctor"
  fi

  STATE="running"
  write_state
  cmd_status
}

cmd_stop() {
  resolve_context
  "$SCRIPT_DIR/cleanup-host-runtime.sh" --run-dir "$RUN_DIR" >/dev/null
  cmd_status
}

COMMAND="${1:-}"
[ -n "$COMMAND" ] || {
  usage
  exit 1
}
shift || true

CLI_RUN_DIR=""
CLI_MANIFEST_ROOT=""
CLI_MODE=""
CLI_ORIGIN=""
CLI_INITIAL_URL=""
CLI_SESSION_KEY="default"
CLI_PROFILE_DIR=""
CLI_CDP_PORT=""
CLI_DISPLAY_NUM=""
CLI_BROWSER_CMD=""
REPAIR=false
CHECK_TYPE=""
TARGET_ID=""
TARGET_URL=""
TARGETS_JSON=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)
      CLI_RUN_DIR="$2"
      shift 2
      ;;
    --mode)
      CLI_MODE="$2"
      shift 2
      ;;
    --manifest-root)
      CLI_MANIFEST_ROOT="$2"
      shift 2
      ;;
    --origin)
      CLI_ORIGIN="$2"
      shift 2
      ;;
    --session-key)
      CLI_SESSION_KEY="$2"
      shift 2
      ;;
    --profile-dir)
      CLI_PROFILE_DIR="$2"
      shift 2
      ;;
    --cdp-port)
      CLI_CDP_PORT="$2"
      shift 2
      ;;
    --display)
      CLI_DISPLAY_NUM="${2#:}"
      shift 2
      ;;
    --browser)
      CLI_BROWSER_CMD="$2"
      shift 2
      ;;
    --check)
      CHECK_TYPE="$2"
      shift 2
      ;;
    --target-id)
      TARGET_ID="$2"
      shift 2
      ;;
    --target-url)
      TARGET_URL="$2"
      shift 2
      ;;
    --targets-json)
      TARGETS_JSON="$2"
      shift 2
      ;;
    --url)
      CLI_INITIAL_URL="$2"
      shift 2
      ;;
    --repair)
      REPAIR=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$COMMAND" in
  start)
    cmd_start
    ;;
  status)
    cmd_status
    ;;
  stop)
    cmd_stop
    ;;
  list-targets)
    cmd_list_targets
    ;;
  check-page)
    cmd_check_page
    ;;
  select-target)
    cmd_select_target
    ;;
  verify)
    cmd_verify
    ;;
  doctor)
    cmd_doctor
    ;;
  ensure-browser)
    cmd_ensure_browser
    ;;
  *)
    usage
    exit 1
    ;;
esac
