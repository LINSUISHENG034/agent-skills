#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/runtime-common.sh"

usage() {
  cat <<'EOF'
Usage:
  assist-lan-session.sh start --run-dir DIR --origin URL --session-key KEY [options]
  assist-lan-session.sh status --run-dir DIR
  assist-lan-session.sh capture --run-dir DIR --origin URL --session-key KEY [options]
  assist-lan-session.sh stop --run-dir DIR

Options:
  --manifest-root DIR
  --novnc-port PORT
  --origin URL
  --profile-dir DIR
  --run-dir DIR
  --session-key KEY
  --vnc-port PORT
EOF
}

die() {
  printf '[assist-lan-session] ERROR: %s\n' "$*" >&2
  exit 1
}

require_arg() {
  local name="$1"
  local value="$2"
  [ -n "$value" ] || die "missing required argument: $name"
}

runtime_helper() {
  "${AGENT_BROWSER_RUNTIME_HELPER:-$SCRIPT_DIR/browser-runtime.sh}" "$@"
}

manifest_helper() {
  "${AGENT_BROWSER_MANIFEST_HELPER:-$SCRIPT_DIR/session-manifest.sh}" "$@"
}

site_registry_helper() {
  "${AGENT_BROWSER_SITE_REGISTRY_HELPER:-$SCRIPT_DIR/site-session-registry.sh}" "$@"
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
  local attempt
  for attempt in 1 2 3 4 5; do
    if ! pid_running "$pid"; then
      rm -f "$(pid_file "$name")"
      return 0
    fi
    sleep 1
  done
  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  rm -f "$(pid_file "$name")"
}

state_file() {
  printf '%s/assist.env\n' "$RUN_DIR"
}

load_state() {
  local file
  file="$(state_file)"
  [ -f "$file" ] || die "no active assisted session"
  # shellcheck disable=SC1090
  source "$file"
}

write_state() {
  mkdir -p "$RUN_DIR" "$LOG_DIR"
  cat >"$(state_file)" <<EOF
ORIGIN=$(printf '%q' "$ORIGIN")
SESSION_KEY=$(printf '%q' "$SESSION_KEY")
PROFILE_DIR=$(printf '%q' "$PROFILE_DIR")
RUN_DIR=$(printf '%q' "$RUN_DIR")
RUNTIME_RUN_DIR=$(printf '%q' "$RUNTIME_RUN_DIR")
MANIFEST_ROOT=$(printf '%q' "$MANIFEST_ROOT")
NOVNC_PORT=$(printf '%q' "$NOVNC_PORT")
VNC_PORT=$(printf '%q' "$VNC_PORT")
LAN_HOST=$(printf '%q' "$LAN_HOST")
LAN_URL=$(printf '%q' "$LAN_URL")
LOG_DIR=$(printf '%q' "$LOG_DIR")
DISPLAY_VALUE=$(printf '%q' "$DISPLAY_VALUE")
CDP_PORT=$(printf '%q' "$CDP_PORT")
BROWSER_PID=$(printf '%q' "$BROWSER_PID")
EOF
}

runtime_value() {
  local key="$1"
  local payload="$2"
  python3 - "$key" "$payload" <<'PY'
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

ensure_overlay_deps() {
  X11VNC_BIN="${AGENT_BROWSER_X11VNC_BIN:-x11vnc}"
  WEBSOCKIFY_BIN="${AGENT_BROWSER_WEBSOCKIFY_BIN:-websockify}"
  NOVNC_ROOT="${AGENT_BROWSER_NOVNC_WEB_ROOT:-/usr/share/novnc}"

  if [[ "$X11VNC_BIN" == */* ]]; then
    [ -x "$X11VNC_BIN" ] || die "missing dependency: $X11VNC_BIN"
  elif ! command -v "$X11VNC_BIN" >/dev/null 2>&1; then
    die "missing dependency: $X11VNC_BIN"
  fi

  if [[ "$WEBSOCKIFY_BIN" == */* ]]; then
    [ -x "$WEBSOCKIFY_BIN" ] || die "missing dependency: $WEBSOCKIFY_BIN"
  elif ! command -v "$WEBSOCKIFY_BIN" >/dev/null 2>&1; then
    die "missing dependency: $WEBSOCKIFY_BIN"
  fi

  [ -d "$NOVNC_ROOT" ] || die "$NOVNC_ROOT not found; install novnc or set AGENT_BROWSER_NOVNC_WEB_ROOT"
}

resolve_context() {
  BASE_ROOT="${HOME}/.agent-browser"
  MANIFEST_ROOT="${CLI_MANIFEST_ROOT:-${MANIFEST_ROOT:-$BASE_ROOT}}"
  SESSION_KEY="${CLI_SESSION_KEY:-${SESSION_KEY:-default}}"
  ORIGIN="${CLI_ORIGIN:-${ORIGIN:-}}"
  PROFILE_DIR="${CLI_PROFILE_DIR:-${PROFILE_DIR:-}}"
  NOVNC_PORT="${CLI_NOVNC_PORT:-${NOVNC_PORT:-${HOST_WEB_ACCESS_NOVNC_PORT:-6084}}}"
  VNC_PORT="${CLI_VNC_PORT:-${VNC_PORT:-${HOST_WEB_ACCESS_VNC_PORT:-5904}}}"

  if [ -n "${CLI_RUN_DIR:-}" ]; then
    RUN_DIR="$CLI_RUN_DIR"
  elif [ -z "${RUN_DIR:-}" ]; then
    RUN_DIR="$(runtime_scoped_path "$BASE_ROOT" assist "$ORIGIN" "$SESSION_KEY")"
  fi

  if [ -f "$(state_file)" ]; then
    load_state
  fi

  MANIFEST_ROOT="${CLI_MANIFEST_ROOT:-${MANIFEST_ROOT:-$BASE_ROOT}}"
  SESSION_KEY="${CLI_SESSION_KEY:-${SESSION_KEY:-default}}"
  ORIGIN="${CLI_ORIGIN:-${ORIGIN:-$ORIGIN}}"
  PROFILE_DIR="${CLI_PROFILE_DIR:-${PROFILE_DIR:-$PROFILE_DIR}}"
  NOVNC_PORT="${CLI_NOVNC_PORT:-${NOVNC_PORT:-${HOST_WEB_ACCESS_NOVNC_PORT:-6084}}}"
  VNC_PORT="${CLI_VNC_PORT:-${VNC_PORT:-${HOST_WEB_ACCESS_VNC_PORT:-5904}}}"
  RUN_DIR="${CLI_RUN_DIR:-${RUN_DIR:-$(runtime_scoped_path "$BASE_ROOT" assist "$ORIGIN" "$SESSION_KEY")}}"
  RUNTIME_RUN_DIR="${RUNTIME_RUN_DIR:-$(runtime_scoped_path "$BASE_ROOT" run "$ORIGIN" "$SESSION_KEY")}"
  LOG_DIR="${LOG_DIR:-$(runtime_scoped_path "$BASE_ROOT" logs "$ORIGIN" "$SESSION_KEY")}"
}

start_assisted() {
  require_arg --run-dir "$RUN_DIR"
  require_arg --origin "$ORIGIN"
  require_arg --session-key "$SESSION_KEY"

  local runtime status_value
  runtime="$(runtime_helper status --run-dir "$RUNTIME_RUN_DIR" --origin "$ORIGIN" --session-key "$SESSION_KEY")"
  status_value="$(runtime_value status "$runtime")"
  [ "$status_value" = "running" ] || die "browser runtime is not running"

  DISPLAY_VALUE="$(runtime_value display "$runtime")"
  PROFILE_DIR="${PROFILE_DIR:-$(runtime_value profile_dir "$runtime")}"
  CDP_PORT="$(runtime_value cdp_port "$runtime")"
  BROWSER_PID="$(runtime_value browser_pid "$runtime")"
  require_arg display "$DISPLAY_VALUE"
  require_arg profile_dir "$PROFILE_DIR"
  require_arg browser_pid "$BROWSER_PID"

  LAN_HOST="${AGENT_BROWSER_NOVNC_PUBLIC_HOST:-$(primary_ipv4 || true)}"
  [ -n "$LAN_HOST" ] || die "unable to determine LAN host for noVNC; set AGENT_BROWSER_NOVNC_PUBLIC_HOST to a LAN-reachable host or IP explicitly"
  if [ "$LAN_HOST" = "127.0.0.1" ] || [ "$LAN_HOST" = "localhost" ]; then
    die "refusing to expose assisted session on loopback; set AGENT_BROWSER_NOVNC_PUBLIC_HOST to a LAN-reachable host or IP explicitly in constrained or container environments"
  fi
  LAN_URL="$(lan_novnc_url "$LAN_HOST" "$NOVNC_PORT")"

  ensure_overlay_deps
  write_state

  if ! pid_running "$(read_pid x11vnc)"; then
    start_process x11vnc "$LOG_DIR/x11vnc.log" \
      env DISPLAY="$DISPLAY_VALUE" \
      "$X11VNC_BIN" -display "$DISPLAY_VALUE" -forever -shared -rfbport "$VNC_PORT" -localhost -nopw
  fi
  if ! pid_running "$(read_pid websockify)"; then
    start_process websockify "$LOG_DIR/websockify.log" \
      "$WEBSOCKIFY_BIN" --web="$NOVNC_ROOT" "0.0.0.0:$NOVNC_PORT" "127.0.0.1:$VNC_PORT"
  fi

  printf 'lan_novnc_url: %s\n' "$LAN_URL"
}

status_assisted() {
  load_state
  printf 'lan_novnc_url: %s\n' "$LAN_URL"
}

capture_assisted() {
  load_state
  require_arg --origin "$ORIGIN"
  require_arg --session-key "$SESSION_KEY"
  require_arg profile_dir "$PROFILE_DIR"

  local browser_pid="${BROWSER_PID:-}"
  if [ -z "$browser_pid" ]; then
    local runtime
    runtime="$(runtime_helper status --run-dir "$RUNTIME_RUN_DIR" --origin "$ORIGIN" --session-key "$SESSION_KEY")"
    browser_pid="$(runtime_value browser_pid "$runtime")"
  fi
  require_arg browser_pid "$browser_pid"

  manifest_helper write \
    --root "$MANIFEST_ROOT" \
    --origin "$ORIGIN" \
    --session-key "$SESSION_KEY" \
    --state ready \
    --browser-pid "$browser_pid" \
    --profile-dir "$PROFILE_DIR" \
    --task-scope assisted \
    --mode assisted-gui \
    --display "$DISPLAY_VALUE" \
    --cdp-port "${CDP_PORT:-}" \
    --novnc-port "$NOVNC_PORT" >/dev/null

  site_registry_helper write \
    --root "$MANIFEST_ROOT" \
    --site "$(site_key "$ORIGIN")" \
    --session-key "$SESSION_KEY" \
    --profile-dir "$PROFILE_DIR" \
    --source-origin "$ORIGIN" >/dev/null

  printf 'lan_novnc_url: %s\n' "$LAN_URL"
}

stop_assisted() {
  load_state
  stop_process websockify
  stop_process x11vnc
  rm -f "$(state_file)"
}

COMMAND="${1:-}"
[ -n "$COMMAND" ] || {
  usage
  exit 1
}
shift || true

CLI_RUN_DIR=""
CLI_MANIFEST_ROOT=""
CLI_NOVNC_PORT=""
CLI_ORIGIN=""
CLI_PROFILE_DIR=""
CLI_SESSION_KEY=""
CLI_VNC_PORT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --manifest-root)
      CLI_MANIFEST_ROOT="$2"
      shift 2
      ;;
    --novnc-port)
      CLI_NOVNC_PORT="$2"
      shift 2
      ;;
    --origin)
      CLI_ORIGIN="$2"
      shift 2
      ;;
    --profile-dir)
      CLI_PROFILE_DIR="$2"
      shift 2
      ;;
    --run-dir)
      CLI_RUN_DIR="$2"
      shift 2
      ;;
    --session-key)
      CLI_SESSION_KEY="$2"
      shift 2
      ;;
    --vnc-port)
      CLI_VNC_PORT="$2"
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

resolve_context

case "$COMMAND" in
  start)
    start_assisted
    ;;
  status)
    status_assisted
    ;;
  capture)
    capture_assisted
    ;;
  stop)
    stop_assisted
    ;;
  *)
    usage
    exit 1
    ;;
esac
