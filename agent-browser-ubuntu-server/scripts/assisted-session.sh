#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  assisted-session.sh start --url URL [options]
  assisted-session.sh status [--run-dir DIR]
  assisted-session.sh capture --origin URL [options]
  assisted-session.sh stop [--run-dir DIR]

Options:
  --block-reason REASON
  --manifest-root DIR
  --novnc-port PORT
  --origin URL
  --profile-dir DIR
  --run-dir DIR
  --session-key KEY
  --url URL
  --vnc-port PORT
EOF
}

log() {
  printf '[assisted-session] %s\n' "$*"
}

die() {
  printf '[assisted-session] ERROR: %s\n' "$*" >&2
  exit 1
}

require_arg() {
  local name="$1"
  local value="$2"
  [ -n "$value" ] || die "missing required argument: $name"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

runtime_helper() {
  "${AGENT_BROWSER_RUNTIME_HELPER:-$SCRIPT_DIR/browser-runtime.sh}" "$@"
}

manifest_helper() {
  "${AGENT_BROWSER_MANIFEST_HELPER:-$SCRIPT_DIR/session-manifest.sh}" "$@"
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

write_state() {
  mkdir -p "$RUN_DIR"
  cat >"$STATE_FILE" <<EOF
URL=$(printf '%q' "$INITIAL_URL")
RUN_DIR=$(printf '%q' "$RUN_DIR")
MANIFEST_ROOT=$(printf '%q' "$MANIFEST_ROOT")
NOVNC_PORT=$(printf '%q' "$NOVNC_PORT")
VNC_PORT=$(printf '%q' "$VNC_PORT")
PROFILE_DIR=$(printf '%q' "$PROFILE_DIR")
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

runtime_status() {
  runtime_helper status --run-dir "$RUNTIME_RUN_DIR"
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

first_page_target_id() {
  local payload="$1"
  python3 - "$payload" <<'PY'
import json
import sys

targets = json.loads(sys.argv[1])
for target in targets:
    if target.get("type") == "page":
        print(target.get("id", ""))
        break
PY
}

status_assisted() {
  local runtime
  runtime="$(runtime_status)"
  printf 'assisted_session: %s\n' "$(pid_running "$(read_pid x11vnc)" && printf 'running' || printf 'stopped')"
  printf 'novnc_url: http://127.0.0.1:%s/vnc.html?autoconnect=1&resize=remote\n' "$NOVNC_PORT"
  printf '%s\n' "$runtime"
}

ensure_runtime_for_assist() {
  local runtime
  runtime="$(runtime_status)"
  if ! printf '%s\n' "$runtime" | grep -q '^runtime: running$'; then
    runtime_helper start --run-dir "$RUNTIME_RUN_DIR" --url "$INITIAL_URL" --mode gui ${PROFILE_DIR:+--profile-dir "$PROFILE_DIR"} >/dev/null
    runtime="$(runtime_status)"
  fi
  printf '%s\n' "$runtime"
}

ensure_overlay_deps() {
  local missing=()
  local dep
  for dep in x11vnc websockify; do
    if ! have_cmd "$dep"; then
      missing+=("$dep")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "missing dependencies: ${missing[*]}"
  fi
  if [ ! -d /usr/share/novnc ]; then
    die "/usr/share/novnc not found; install novnc or adjust the script for your distribution"
  fi
}

start_assisted() {
  require_arg --url "$INITIAL_URL"
  local runtime display runtime_mode
  runtime="$(ensure_runtime_for_assist)"
  runtime_mode="$(runtime_value mode "$runtime")"
  display="$(runtime_value display "$runtime")"
  PROFILE_DIR="$(runtime_value profile_dir "$runtime")"
  [ "$runtime_mode" = "gui" ] || die "assisted flow requires runtime GUI mode"
  [ -n "$display" ] || die "runtime did not expose a display"

  ensure_overlay_deps
  write_state

  if ! pid_running "$(read_pid x11vnc)"; then
    start_process x11vnc "$LOG_DIR/x11vnc.log" \
      env DISPLAY="$display" \
      x11vnc -display "$display" -forever -shared -rfbport "$VNC_PORT" -localhost -nopw
  fi

  if ! pid_running "$(read_pid websockify)"; then
    start_process websockify "$LOG_DIR/websockify.log" \
      websockify --web=/usr/share/novnc "0.0.0.0:$NOVNC_PORT" "localhost:$VNC_PORT"
  fi

  local target_id challenge login_wall
  target_id="$(first_page_target_id "$(runtime_helper list-targets --run-dir "$RUNTIME_RUN_DIR")")"
  challenge=""
  login_wall=""
  if [ -n "$target_id" ]; then
    challenge="$(runtime_helper check-page --run-dir "$RUNTIME_RUN_DIR" --cdp-port "$CDP_PORT" --target-id "$target_id" --check challenge 2>/dev/null || true)"
    login_wall="$(runtime_helper check-page --run-dir "$RUNTIME_RUN_DIR" --cdp-port "$CDP_PORT" --target-id "$target_id" --check login-wall 2>/dev/null || true)"
  fi

  log "noVNC URL: http://127.0.0.1:$NOVNC_PORT/vnc.html?autoconnect=1&resize=remote"
  if printf '%s' "$challenge" | grep -q '"hasChallenge": true'; then
    log "next action: open the noVNC URL, wait for the challenge to clear or complete it, and leave the protected page loaded"
  elif printf '%s' "$login_wall" | grep -q '"hasLoginWall": true'; then
    log "next action: open the noVNC URL, sign in, complete any MFA, and leave the final page loaded"
  else
    log "next action: open the noVNC URL only if local recovery did not already clear the block"
  fi
}

capture_session() {
  require_arg --origin "$ORIGIN"
  local runtime target_json target_id challenge_json login_json page_json browser_pid display cdp_port
  runtime="$(runtime_status)"
  if ! printf '%s\n' "$runtime" | grep -q '^runtime: running$'; then
    die "no verified browser runtime is available"
  fi

  browser_pid="$(runtime_value browser_pid "$runtime")"
  display="$(runtime_value display "$runtime")"
  cdp_port="$(runtime_value cdp_port "$runtime")"
  PROFILE_DIR="$(runtime_value profile_dir "$runtime")"
  require_arg browser_pid "$browser_pid"
  require_arg cdp_port "$cdp_port"

  target_json="$(runtime_helper list-targets --run-dir "$RUNTIME_RUN_DIR")"
  target_id="$(first_page_target_id "$target_json")"
  [ -n "$target_id" ] || die "no page target is available for capture"

  challenge_json="$(runtime_helper check-page --run-dir "$RUNTIME_RUN_DIR" --cdp-port "$cdp_port" --target-id "$target_id" --check challenge)"
  login_json="$(runtime_helper check-page --run-dir "$RUNTIME_RUN_DIR" --cdp-port "$cdp_port" --target-id "$target_id" --check login-wall)"
  page_json="$(runtime_helper check-page --run-dir "$RUNTIME_RUN_DIR" --cdp-port "$cdp_port" --target-id "$target_id" --check page-info)"

  if printf '%s' "$challenge_json" | grep -q '"hasChallenge": true'; then
    die "verification has not succeeded yet; challenge page still active"
  fi
  if printf '%s' "$login_json" | grep -q '"hasLoginWall": true'; then
    die "verification has not succeeded yet; login wall still active"
  fi

  manifest_helper write \
    --root "$MANIFEST_ROOT" \
    --origin "$ORIGIN" \
    --session-key "$SESSION_KEY" \
    --state ready \
    --browser-pid "$browser_pid" \
    --cdp-port "$cdp_port" \
    --target-id "$target_id" \
    --profile-dir "$PROFILE_DIR" \
    --mode assisted-gui \
    --display "$display" \
    ${BLOCK_REASON:+--block-reason "$BLOCK_REASON"} >/dev/null

  printf '%s\n' "$page_json"
}

stop_assisted() {
  stop_process websockify
  stop_process x11vnc
  log "assisted overlay stopped"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-}"
[ -n "$COMMAND" ] || {
  usage
  exit 1
}
shift || true

RUN_DIR=""
RUNTIME_RUN_DIR=""
MANIFEST_ROOT=""
INITIAL_URL=""
PROFILE_DIR=""
NOVNC_PORT=""
VNC_PORT=""
ORIGIN=""
SESSION_KEY="default"
BLOCK_REASON=""
CDP_PORT=""
LOG_DIR=""

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
    --url)
      INITIAL_URL="$2"
      shift 2
      ;;
    --profile-dir)
      PROFILE_DIR="$2"
      shift 2
      ;;
    --novnc-port)
      NOVNC_PORT="$2"
      shift 2
      ;;
    --vnc-port)
      VNC_PORT="$2"
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
    --block-reason)
      BLOCK_REASON="$2"
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
CLI_INITIAL_URL="$INITIAL_URL"
CLI_PROFILE_DIR="$PROFILE_DIR"
CLI_NOVNC_PORT="$NOVNC_PORT"
CLI_VNC_PORT="$VNC_PORT"

BASE_ROOT="${HOME}/.agent-browser"
RUN_DIR="${RUN_DIR:-$BASE_ROOT/assist}"
RUNTIME_RUN_DIR="${RUNTIME_RUN_DIR:-$BASE_ROOT/run}"
MANIFEST_ROOT="${MANIFEST_ROOT:-$BASE_ROOT}"
INITIAL_URL="${INITIAL_URL:-https://example.com}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PORT="${VNC_PORT:-5900}"
LOG_DIR="${LOG_DIR:-$BASE_ROOT/logs}"
STATE_FILE="$RUN_DIR/assist.env"
load_state

RUN_DIR="${CLI_RUN_DIR:-$RUN_DIR}"
MANIFEST_ROOT="${CLI_MANIFEST_ROOT:-$MANIFEST_ROOT}"
INITIAL_URL="${CLI_INITIAL_URL:-$INITIAL_URL}"
PROFILE_DIR="${CLI_PROFILE_DIR:-$PROFILE_DIR}"
NOVNC_PORT="${CLI_NOVNC_PORT:-$NOVNC_PORT}"
VNC_PORT="${CLI_VNC_PORT:-$VNC_PORT}"
STATE_FILE="$RUN_DIR/assist.env"

case "$COMMAND" in
  start)
    start_assisted
    ;;
  status)
    status_assisted
    ;;
  capture)
    capture_session
    ;;
  stop)
    stop_assisted
    ;;
  *)
    usage
    exit 1
    ;;
esac
