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
  browser-runtime.sh ensure-browser [options]

Options:
  --browser CMD
  --cdp-port PORT
  --display NUM
  --mode headless|gui
  --origin URL
  --profile-dir DIR
  --run-dir DIR
  --session-key KEY
  --url URL
EOF
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

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
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
CDP_PORT=$(printf '%q' "$CDP_PORT")
DISPLAY_NUM=$(printf '%q' "$DISPLAY_NUM")
BROWSER_CMD=$(printf '%q' "$BROWSER_CMD")
STATE=$(printf '%q' "$STATE")
EOF
}

resolve_context() {
  BASE_ROOT="${HOME}/.agent-browser"
  SESSION_KEY="${SESSION_KEY:-default}"
  MODE="${CLI_MODE:-${MODE:-headless}}"
  ORIGIN="${CLI_ORIGIN:-${ORIGIN:-}}"
  INITIAL_URL="${CLI_INITIAL_URL:-${INITIAL_URL:-}}"
  BROWSER_CMD="${CLI_BROWSER_CMD:-${BROWSER_CMD:-}}"
  CDP_PORT="${CLI_CDP_PORT:-${CDP_PORT:-19222}}"
  DISPLAY_NUM="${CLI_DISPLAY_NUM:-${DISPLAY_NUM:-88}}"

  if [ -z "$ORIGIN" ] && [ -n "$INITIAL_URL" ]; then
    ORIGIN="$(derive_origin "$INITIAL_URL")"
  fi
  if [ -z "$ORIGIN" ]; then
    ORIGIN="https://example.com"
  fi
  if [ -z "$INITIAL_URL" ]; then
    INITIAL_URL="$ORIGIN"
  fi

  if [ -z "${CLI_RUN_DIR:-}" ]; then
    RUN_DIR="${RUN_DIR:-$(runtime_scoped_path "$BASE_ROOT" run "$ORIGIN" "$SESSION_KEY")}"
  else
    RUN_DIR="$CLI_RUN_DIR"
  fi
  STATE_FILE="$RUN_DIR/runtime.env"
  load_state

  MODE="${CLI_MODE:-${MODE:-headless}}"
  ORIGIN="${CLI_ORIGIN:-${ORIGIN:-$ORIGIN}}"
  INITIAL_URL="${CLI_INITIAL_URL:-${INITIAL_URL:-$ORIGIN}}"
  SESSION_KEY="${CLI_SESSION_KEY:-${SESSION_KEY:-default}}"
  CDP_PORT="${CLI_CDP_PORT:-${CDP_PORT:-19222}}"
  DISPLAY_NUM="${CLI_DISPLAY_NUM:-${DISPLAY_NUM:-88}}"
  BROWSER_CMD="${CLI_BROWSER_CMD:-${BROWSER_CMD:-}}"
  LOG_DIR="${LOG_DIR:-$(runtime_scoped_path "$BASE_ROOT" logs "$ORIGIN" "$SESSION_KEY")}"
  PROFILE_DIR="${CLI_PROFILE_DIR:-${PROFILE_DIR:-$(runtime_scoped_path "$BASE_ROOT" profiles "$ORIGIN" "$SESSION_KEY")}}"
  STATE="${STATE:-stopped}"
}

runtime_status() {
  local browser_pid
  browser_pid="$(read_pid browser)"
  if pid_running "$browser_pid"; then
    STATE="running"
  elif [ "$STATE" != "closed" ]; then
    STATE="stopped"
  fi
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
cdp_port: $CDP_PORT
display: $DISPLAY_NUM
browser_pid: $(read_pid browser)
EOF
}

cmd_ensure_browser() {
  resolve_context
  if ! BROWSER_CMD="$(detect_browser)"; then
    die "missing browser dependency: google-chrome/chromium"
  fi
  printf '%s\n' "$BROWSER_CMD"
}

cmd_list_targets() {
  resolve_context
  if have_cmd curl && curl -s --max-time 1 "http://127.0.0.1:${CDP_PORT}/json/list" >/dev/null 2>&1; then
    curl -s --max-time 2 "http://127.0.0.1:${CDP_PORT}/json/list"
    return 0
  fi
  printf '[]\n'
}

cmd_start() {
  resolve_context
  require_arg --url "$INITIAL_URL"

  if [ -z "$BROWSER_CMD" ]; then
    BROWSER_CMD="$(detect_browser || true)"
  fi
  [ -n "$BROWSER_CMD" ] || die "missing browser dependency: google-chrome/chromium"

  mkdir -p "$RUN_DIR" "$LOG_DIR" "$PROFILE_DIR"
  local log_file="$LOG_DIR/browser.log"
  : >"$log_file"

  "$BROWSER_CMD" >>"$log_file" 2>&1 &
  local browser_pid=$!
  printf '%s\n' "$browser_pid" >"$(pid_file browser)"
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
CLI_MODE=""
CLI_ORIGIN=""
CLI_INITIAL_URL=""
CLI_SESSION_KEY="default"
CLI_PROFILE_DIR=""
CLI_CDP_PORT=""
CLI_DISPLAY_NUM=""
CLI_BROWSER_CMD=""

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
    --origin)
      CLI_ORIGIN="$2"
      shift 2
      ;;
    --url)
      CLI_INITIAL_URL="$2"
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
      CLI_DISPLAY_NUM="$2"
      shift 2
      ;;
    --browser)
      CLI_BROWSER_CMD="$2"
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
  ensure-browser)
    cmd_ensure_browser
    ;;
  *)
    usage
    exit 1
    ;;
esac
