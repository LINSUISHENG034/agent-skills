#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  browser-login-stack.sh start [options]
  browser-login-stack.sh stop [options]
  browser-login-stack.sh status [options]

Options:
  --browser CMD         Browser binary to use
  --cdp-port PORT       Chrome DevTools port (default: 9222)
  --display NUM         X display number without ":" (default: 77)
  --host IP             Host IP to print in status output
  --log-dir PATH        Log directory (default: ~/.remote-browser-logs)
  --novnc-port PORT     noVNC/websockify port (default: 6080)
  --profile-dir PATH    Browser profile directory (default: ~/.remote-browser-profile)
  --run-dir PATH        Runtime state directory (default: ~/.remote-browser-run)
  --screen WxHxD        Xvfb screen geometry (default: 1600x900x24)
  --url URL             Initial browser URL (default: https://example.com)
  --vnc-port PORT       x11vnc port bound on localhost (default: 5900)

Examples:
  browser-login-stack.sh start --url 'https://linux.do/'
  browser-login-stack.sh status
  browser-login-stack.sh stop
EOF
}

log() {
  printf '[browser-login-stack] %s\n' "$*"
}

die() {
  printf '[browser-login-stack] ERROR: %s\n' "$*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
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

write_state() {
  mkdir -p "$RUN_DIR"
  cat >"$STATE_FILE" <<EOF
DISPLAY_NUM=$(printf '%q' "$DISPLAY_NUM")
SCREEN_GEOMETRY=$(printf '%q' "$SCREEN_GEOMETRY")
VNC_PORT=$(printf '%q' "$VNC_PORT")
NOVNC_PORT=$(printf '%q' "$NOVNC_PORT")
CDP_PORT=$(printf '%q' "$CDP_PORT")
PROFILE_DIR=$(printf '%q' "$PROFILE_DIR")
LOG_DIR=$(printf '%q' "$LOG_DIR")
RUN_DIR=$(printf '%q' "$RUN_DIR")
HOST_IP=$(printf '%q' "$HOST_IP")
INITIAL_URL=$(printf '%q' "$INITIAL_URL")
BROWSER_CMD=$(printf '%q' "$BROWSER_CMD")
EOF
  chmod 600 "$STATE_FILE"
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

pid_file() {
  printf '%s/%s.pid\n' "$RUN_DIR" "$1"
}

read_pid() {
  local name="$1"
  local file
  file="$(pid_file "$name")"
  if [ -f "$file" ]; then
    cat "$file"
  fi
}

pid_running() {
  local pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

collect_listener_output() {
  if have_cmd lsof; then
    lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -E "(${VNC_PORT}|${NOVNC_PORT}|${CDP_PORT})" || true
    return 0
  fi

  if have_cmd ss; then
    ss -ltnp 2>/dev/null | grep -E ":(${VNC_PORT}|${NOVNC_PORT}|${CDP_PORT})\\b" || true
  fi
}

ports_in_use() {
  [ -n "$(collect_listener_output)" ]
}

process_status_line() {
  local name="$1"
  local pid
  pid="$(read_pid "$name")"
  if pid_running "$pid"; then
    printf '%-10s running (pid %s)\n' "$name" "$pid"
  else
    printf '%-10s stopped\n' "$name"
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

  if ! pid_running "$pid"; then
    die "$name failed to start; inspect $logfile"
  fi
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

require_start_dependencies() {
  local missing=()
  local browser

  for browser in Xvfb x11vnc websockify; do
    if ! have_cmd "$browser"; then
      missing+=("$browser")
    fi
  done

  if ! BROWSER_CMD="$(detect_browser)"; then
    missing+=("google-chrome/chromium")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    die "missing dependencies: ${missing[*]}"
  fi

  if [ ! -d /usr/share/novnc ]; then
    die "/usr/share/novnc not found; install novnc or adjust the script for your distribution"
  fi
}

check_not_running() {
  local name pid
  for name in xvfb x11vnc websockify browser; do
    pid="$(read_pid "$name")"
    if pid_running "$pid"; then
      die "stack already running for $name (pid $pid); run stop or status first"
    fi
  done

  if ports_in_use; then
    die "configured ports are already in use; inspect listeners with status or choose different ports"
  fi
}

resolve_host_ip() {
  if [ -n "${HOST_IP:-}" ]; then
    return 0
  fi

  HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  HOST_IP="${HOST_IP:-127.0.0.1}"
}

wait_for_display() {
  local socket="/tmp/.X11-unix/X${DISPLAY_NUM}"
  local _i

  for _i in 1 2 3 4 5 6 7 8 9 10; do
    if [ -S "$socket" ]; then
      if have_cmd xdpyinfo; then
        if DISPLAY=":$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1; then
          return 0
        fi
      else
        return 0
      fi
    fi
    sleep 1
  done

  die "Xvfb did not become ready on :$DISPLAY_NUM"
}

start_stack() {
  require_start_dependencies
  resolve_host_ip
  mkdir -p "$PROFILE_DIR" "$LOG_DIR" "$RUN_DIR"
  check_not_running
  write_state

  start_process xvfb "$LOG_DIR/xvfb.log" \
    Xvfb ":$DISPLAY_NUM" -screen 0 "$SCREEN_GEOMETRY" -ac +extension RANDR
  wait_for_display

  start_process x11vnc "$LOG_DIR/x11vnc.log" \
    env DISPLAY=":$DISPLAY_NUM" \
    x11vnc -display ":$DISPLAY_NUM" -forever -shared -rfbport "$VNC_PORT" -localhost -nopw

  start_process websockify "$LOG_DIR/websockify.log" \
    websockify --web=/usr/share/novnc "0.0.0.0:$NOVNC_PORT" "localhost:$VNC_PORT"

  start_process browser "$LOG_DIR/browser.log" \
    env DISPLAY=":$DISPLAY_NUM" \
    "$BROWSER_CMD" \
    --no-first-run \
    --no-default-browser-check \
    --user-data-dir="$PROFILE_DIR" \
    --remote-debugging-address=0.0.0.0 \
    --remote-debugging-port="$CDP_PORT" \
    --new-window "$INITIAL_URL"

  log "stack started"
  log "noVNC URL: http://$HOST_IP:$NOVNC_PORT/vnc.html?autoconnect=1&resize=remote"
  log "DevTools URL on host: http://127.0.0.1:$CDP_PORT/json"
  log "Windows tunnel: ssh -L $NOVNC_PORT:127.0.0.1:$NOVNC_PORT -L $CDP_PORT:127.0.0.1:$CDP_PORT USER@$HOST_IP"
  log "profile dir: $PROFILE_DIR"
}

stop_stack() {
  stop_process browser
  stop_process websockify
  stop_process x11vnc
  stop_process xvfb
  log "stack stopped"

  if ports_in_use; then
    log "warning: listeners still exist on configured ports; they may belong to another session"
    collect_listener_output
  fi
}

status_stack() {
  resolve_host_ip
  printf 'host_ip: %s\n' "$HOST_IP"
  printf 'display: :%s\n' "$DISPLAY_NUM"
  printf 'profile_dir: %s\n' "$PROFILE_DIR"
  printf 'log_dir: %s\n' "$LOG_DIR"
  printf 'noVNC: http://%s:%s/vnc.html?autoconnect=1&resize=remote\n' "$HOST_IP" "$NOVNC_PORT"
  printf 'DevTools on host: http://127.0.0.1:%s/json\n' "$CDP_PORT"

  process_status_line xvfb
  process_status_line x11vnc
  process_status_line websockify
  process_status_line browser

  if ports_in_use; then
    printf 'listeners:\n'
    collect_listener_output
  fi

  if have_cmd curl; then
    local novnc_health devtools_health
    novnc_health="$(curl -I -s --max-time 3 "http://127.0.0.1:${NOVNC_PORT}/vnc.html" | head -n 1 || true)"
    devtools_health="$(curl -s --max-time 3 "http://127.0.0.1:${CDP_PORT}/json/version" | head -c 160 || true)"
    printf 'noVNC health: '
    printf '%s\n' "${novnc_health:-unreachable}"
    printf 'DevTools health: '
    printf '%s\n' "${devtools_health:-unreachable}"
  fi
}

COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  usage
  exit 1
fi
shift || true
ARGS=("$@")

DISPLAY_NUM="${DISPLAY_NUM:-77}"
SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1600x900x24}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
CDP_PORT="${CDP_PORT:-9222}"
PROFILE_DIR="${PROFILE_DIR:-$HOME/.remote-browser-profile}"
LOG_DIR="${LOG_DIR:-$HOME/.remote-browser-logs}"
RUN_DIR="${RUN_DIR:-$HOME/.remote-browser-run}"
HOST_IP="${HOST_IP:-}"
INITIAL_URL="${INITIAL_URL:-https://example.com}"
BROWSER_CMD="${BROWSER_CMD:-}"
STATE_FILE="$RUN_DIR/stack.env"

for ((i = 0; i < ${#ARGS[@]}; i++)); do
  if [ "${ARGS[$i]}" = "--run-dir" ] && [ $((i + 1)) -lt ${#ARGS[@]} ]; then
    RUN_DIR="${ARGS[$((i + 1))]}"
    STATE_FILE="$RUN_DIR/stack.env"
  fi
done

load_state

set -- "${ARGS[@]}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --browser)
      BROWSER_CMD="$2"
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
    --host)
      HOST_IP="$2"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="$2"
      shift 2
      ;;
    --novnc-port)
      NOVNC_PORT="$2"
      shift 2
      ;;
    --profile-dir)
      PROFILE_DIR="$2"
      shift 2
      ;;
    --run-dir)
      RUN_DIR="$2"
      STATE_FILE="$RUN_DIR/stack.env"
      shift 2
      ;;
    --screen)
      SCREEN_GEOMETRY="$2"
      shift 2
      ;;
    --url)
      INITIAL_URL="$2"
      shift 2
      ;;
    --vnc-port)
      VNC_PORT="$2"
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
    start_stack
    ;;
  stop)
    stop_stack
    ;;
  status)
    status_stack
    ;;
  *)
    usage
    exit 1
    ;;
esac
