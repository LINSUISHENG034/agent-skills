#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  browser-runtime.sh start --url URL [--mode headless|gui] [options]
  browser-runtime.sh status [--run-dir DIR]
  browser-runtime.sh list-targets [--run-dir DIR] [--cdp-port PORT]
  browser-runtime.sh check-page --cdp-port PORT --check TYPE [--target-id ID]
  browser-runtime.sh attach --origin URL --session-key KEY [--manifest-root DIR]
  browser-runtime.sh verify --origin URL --session-key KEY [--manifest-root DIR]
  browser-runtime.sh stop [--run-dir DIR]

Options:
  --browser CMD
  --cdp-port PORT
  --display NUM
  --manifest-root DIR
  --mode MODE
  --profile-dir DIR
  --run-dir DIR
  --url URL
EOF
}

log() {
  printf '[browser-runtime] %s\n' "$*"
}

die() {
  printf '[browser-runtime] ERROR: %s\n' "$*" >&2
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

detect_browser() {
  if [ -n "${BROWSER_CMD:-}" ]; then
    printf '%s\n' "$BROWSER_CMD"
    return 0
  fi

  local candidate
  for candidate in google-chrome chromium chromium-browser; do
    if have_cmd "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

pid_running() {
  local pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
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

write_state() {
  mkdir -p "$RUN_DIR"
  cat >"$STATE_FILE" <<EOF
MODE=$(printf '%q' "$MODE")
INITIAL_URL=$(printf '%q' "$INITIAL_URL")
PROFILE_DIR=$(printf '%q' "$PROFILE_DIR")
RUN_DIR=$(printf '%q' "$RUN_DIR")
LOG_DIR=$(printf '%q' "$LOG_DIR")
CDP_PORT=$(printf '%q' "$CDP_PORT")
DISPLAY_NUM=$(printf '%q' "$DISPLAY_NUM")
BROWSER_CMD=$(printf '%q' "$BROWSER_CMD")
EOF
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
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
}

stop_process() {
  local name="$1"
  local pid
  pid="$(read_pid "$name")"

  if ! pid_running "$pid"; then
    rm -f "$(pid_file "$name")"
    return 0
  fi

  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true

  local _i
  for _i in 1 2 3 4 5; do
    if ! pid_running "$pid"; then
      rm -f "$(pid_file "$name")"
      return 0
    fi
    sleep 1
  done

  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  rm -f "$(pid_file "$name")"
}

wait_for_display() {
  local socket="/tmp/.X11-unix/X${DISPLAY_NUM}"
  local _i

  for _i in 1 2 3 4 5 6 7 8 9 10; do
    if [ -S "$socket" ]; then
      if ! have_cmd xdpyinfo || DISPLAY=":$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done

  die "Xvfb did not become ready on :$DISPLAY_NUM"
}

wait_for_cdp() {
  local _i
  if ! have_cmd curl; then
    return 0
  fi

  for _i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -s --max-time 2 "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  die "CDP did not become ready on port $CDP_PORT"
}

runtime_browser_pid() {
  read_pid browser
}

runtime_xvfb_pid() {
  read_pid xvfb
}

runtime_running() {
  pid_running "$(runtime_browser_pid)"
}

manifest_helper() {
  "${AGENT_BROWSER_MANIFEST_HELPER:-$SCRIPT_DIR/session-manifest.sh}" "$@"
}

cdp_eval() {
  "${AGENT_BROWSER_CDP_EVAL:-$SCRIPT_DIR/cdp-eval.py}" "$@"
}

default_paths() {
  local base_root
  base_root="${HOME}/.agent-browser"
  RUN_DIR="${RUN_DIR:-$base_root/run}"
  MANIFEST_ROOT="${MANIFEST_ROOT:-$base_root}"
  PROFILE_DIR="${PROFILE_DIR:-$base_root/profiles/default}"
  LOG_DIR="${LOG_DIR:-$base_root/logs}"
  MODE="${MODE:-headless}"
  INITIAL_URL="${INITIAL_URL:-https://example.com}"
  CDP_PORT="${CDP_PORT:-19222}"
  DISPLAY_NUM="${DISPLAY_NUM:-88}"
  STATE_FILE="$RUN_DIR/runtime.env"
}

require_browser_deps() {
  if ! BROWSER_CMD="$(detect_browser)"; then
    die "missing browser dependency: google-chrome/chromium"
  fi
  if [ "$MODE" = "gui" ] && ! have_cmd Xvfb; then
    die "missing dependency: Xvfb"
  fi
}

start_runtime() {
  require_browser_deps
  mkdir -p "$PROFILE_DIR" "$LOG_DIR" "$RUN_DIR"
  if runtime_running; then
    die "browser runtime already running; use stop or status first"
  fi

  write_state

  if [ "$MODE" = "gui" ]; then
    start_process xvfb "$LOG_DIR/xvfb.log" \
      Xvfb ":$DISPLAY_NUM" -screen 0 1600x900x24 -ac +extension RANDR
    wait_for_display

    start_process browser "$LOG_DIR/browser.log" \
      env DISPLAY=":$DISPLAY_NUM" \
      "$BROWSER_CMD" \
      --no-first-run \
      --no-default-browser-check \
      --user-data-dir="$PROFILE_DIR" \
      --remote-debugging-address=127.0.0.1 \
      --remote-debugging-port="$CDP_PORT" \
      --new-window "$INITIAL_URL"
  else
    start_process browser "$LOG_DIR/browser.log" \
      "$BROWSER_CMD" \
      --headless=new \
      --disable-gpu \
      --no-first-run \
      --no-default-browser-check \
      --user-data-dir="$PROFILE_DIR" \
      --remote-debugging-address=127.0.0.1 \
      --remote-debugging-port="$CDP_PORT" \
      "$INITIAL_URL"
  fi

  wait_for_cdp
  log "runtime started"
  log "mode: $MODE"
  log "profile dir: $PROFILE_DIR"
  log "DevTools URL on host: http://127.0.0.1:$CDP_PORT/json"
}

status_runtime() {
  printf 'runtime: %s\n' "$(runtime_running && printf 'running' || printf 'stopped')"
  printf 'mode: %s\n' "$MODE"
  printf 'url: %s\n' "$INITIAL_URL"
  printf 'profile_dir: %s\n' "$PROFILE_DIR"
  printf 'run_dir: %s\n' "$RUN_DIR"
  printf 'cdp_port: %s\n' "$CDP_PORT"
  printf 'browser_pid: %s\n' "$(runtime_browser_pid || true)"
  if [ "$MODE" = "gui" ] || [ -n "$(runtime_xvfb_pid || true)" ]; then
    printf 'xvfb_pid: %s\n' "$(runtime_xvfb_pid || true)"
    printf 'display: :%s\n' "$DISPLAY_NUM"
  fi
  if runtime_running && have_cmd curl; then
    printf 'cdp_health: %s\n' "$(curl -s --max-time 3 "http://127.0.0.1:${CDP_PORT}/json/version" | head -c 160 || true)"
  fi
}

list_targets() {
  local port
  port="${CDP_PORT}"
  if ! runtime_running && [ ! -f "$STATE_FILE" ]; then
    printf '[]\n'
    return 0
  fi
  if ! have_cmd curl; then
    die "curl is required to list CDP targets"
  fi
  curl -s --max-time 3 "http://127.0.0.1:${port}/json/list" || printf '[]\n'
}

check_page() {
  require_arg --cdp-port "$CDP_PORT"
  require_arg --check "$CHECK_TYPE"
  cdp_eval --port "$CDP_PORT" ${TARGET_ID:+--target-id "$TARGET_ID"} --check "$CHECK_TYPE"
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
    sys.exit(1)
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

load_manifest() {
  manifest_helper show --root "$MANIFEST_ROOT" --origin "$ORIGIN" --session-key "$SESSION_KEY"
}

attach_session() {
  require_arg --origin "$ORIGIN"
  require_arg --session-key "$SESSION_KEY"
  local manifest browser_pid
  manifest="$(load_manifest)" || exit $?
  browser_pid="$(manifest_field browser_pid "$manifest" || true)"
  [ -n "$browser_pid" ] || die "manifest missing browser_pid"
  pid_running "$browser_pid" || die "browser is not running for manifest $SESSION_KEY"
  printf '%s\n' "$manifest"
}

verify_session() {
  require_arg --origin "$ORIGIN"
  require_arg --session-key "$SESSION_KEY"
  local manifest browser_pid cdp_port target_id targets
  manifest="$(load_manifest)" || exit $?
  browser_pid="$(manifest_field browser_pid "$manifest" || true)"
  cdp_port="$(manifest_field cdp_port "$manifest" || true)"
  target_id="$(manifest_field target_id "$manifest" || true)"

  if [ -z "$browser_pid" ] || ! pid_running "$browser_pid"; then
    manifest_helper mark-stale --root "$MANIFEST_ROOT" --origin "$ORIGIN" --session-key "$SESSION_KEY" --reason "browser process is not running" >/dev/null || true
    die "browser is not running for manifest $SESSION_KEY"
  fi

  if [ -n "$cdp_port" ] && have_cmd curl; then
    curl -s --max-time 3 "http://127.0.0.1:${cdp_port}/json/version" >/dev/null || die "CDP endpoint is unreachable for manifest $SESSION_KEY"
    if [ -n "$target_id" ]; then
      targets="$(curl -s --max-time 3 "http://127.0.0.1:${cdp_port}/json/list")"
      printf '%s' "$targets" | grep -q "\"id\":\"${target_id}\"" || die "target_id is no longer present for manifest $SESSION_KEY"
    fi
  fi

  printf '%s\n' "$manifest"
}

stop_runtime() {
  stop_process browser
  stop_process xvfb
  log "runtime stopped"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-}"
[ -n "$COMMAND" ] || {
  usage
  exit 1
}
shift || true

RUN_DIR=""
MANIFEST_ROOT=""
MODE=""
INITIAL_URL=""
PROFILE_DIR=""
CDP_PORT=""
DISPLAY_NUM=""
BROWSER_CMD=""
CHECK_TYPE=""
TARGET_ID=""
ORIGIN=""
SESSION_KEY=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --manifest-root)
      MANIFEST_ROOT="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --url)
      INITIAL_URL="$2"
      shift 2
      ;;
    --profile-dir)
      PROFILE_DIR="$2"
      shift 2
      ;;
    --cdp-port)
      CDP_PORT="$2"
      shift 2
      ;;
    --display)
      DISPLAY_NUM="${2#:}"
      shift 2
      ;;
    --browser)
      BROWSER_CMD="$2"
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
    --origin)
      ORIGIN="$2"
      shift 2
      ;;
    --session-key)
      SESSION_KEY="$2"
      shift 2
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

CLI_RUN_DIR="$RUN_DIR"
CLI_MANIFEST_ROOT="$MANIFEST_ROOT"
CLI_MODE="$MODE"
CLI_INITIAL_URL="$INITIAL_URL"
CLI_PROFILE_DIR="$PROFILE_DIR"
CLI_CDP_PORT="$CDP_PORT"
CLI_DISPLAY_NUM="$DISPLAY_NUM"
CLI_BROWSER_CMD="$BROWSER_CMD"

default_paths
load_state

RUN_DIR="${CLI_RUN_DIR:-$RUN_DIR}"
MANIFEST_ROOT="${CLI_MANIFEST_ROOT:-$MANIFEST_ROOT}"
MODE="${CLI_MODE:-$MODE}"
INITIAL_URL="${CLI_INITIAL_URL:-$INITIAL_URL}"
PROFILE_DIR="${CLI_PROFILE_DIR:-$PROFILE_DIR}"
CDP_PORT="${CLI_CDP_PORT:-$CDP_PORT}"
DISPLAY_NUM="${CLI_DISPLAY_NUM:-$DISPLAY_NUM}"
BROWSER_CMD="${CLI_BROWSER_CMD:-$BROWSER_CMD}"
STATE_FILE="$RUN_DIR/runtime.env"

case "$COMMAND" in
  start)
    require_arg --url "$INITIAL_URL"
    case "$MODE" in
      headless|gui) ;;
      *)
        die "--mode must be headless or gui"
        ;;
    esac
    start_runtime
    ;;
  status)
    status_runtime
    ;;
  list-targets)
    list_targets
    ;;
  check-page)
    check_page
    ;;
  attach)
    attach_session
    ;;
  verify)
    verify_session
    ;;
  stop)
    stop_runtime
    ;;
  *)
    usage
    exit 1
    ;;
esac
