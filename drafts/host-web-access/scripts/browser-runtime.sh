#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  browser-runtime.sh start --run-dir DIR --profile-dir DIR --origin URL [options]
  browser-runtime.sh status --run-dir DIR
  browser-runtime.sh stop --run-dir DIR
  browser-runtime.sh list-targets --run-dir DIR
  browser-runtime.sh ensure-browser --run-dir DIR --profile-dir DIR --origin URL

Options:
  --browser CMD
  --cdp-port PORT
  --display NUM
  --session-key KEY
  --url URL
EOF
}

die() {
  printf '[browser-runtime] ERROR: %s\n' "$*" >&2
  exit 1
}

run_dir=""
log_dir=""
state_file=""

init_run_dir() {
  run_dir="${run_dir:-$HOME/.agent-browser/run/default}"
  log_dir="$run_dir/logs"
  state_file="$run_dir/runtime.env"
  mkdir -p "$run_dir" "$log_dir"
}

read_state() {
  if [ -f "$state_file" ]; then
    source "$state_file"
  fi
}

write_state() {
  cat >"$state_file" <<EOF
MODE=$mode
ORIGIN=$origin
SESSION_KEY=$session_key
PROFILE_DIR=$profile_dir
RUN_DIR=$run_dir
CDP_PORT=$cdp_port
DISPLAY_NUM=$display_num
INITIAL_URL=$initial_url
STATE=$state
state=$state
EOF
}

pid_file() {
  printf '%s/%s.pid\n' "$run_dir" "$1"
}

read_pid() {
  local path
  path="$(pid_file "$1")"
  if [ -f "$path" ]; then
    cat "$path"
  fi
}

write_pid() {
  printf '%s\n' "$2" >"$(pid_file "$1")"
}

start_browser() {
  local cmd="${browser_cmd:-sleep 600}"
  nohup $cmd >/dev/null 2>&1 &
  write_pid browser "$!"
}

stop_pid() {
  local key="$1"
  local path pid
  path="$(pid_file "$key")"
  if [ -f "$path" ]; then
    pid="$(cat "$path")"
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 0.5
      kill -0 "$pid" >/dev/null 2>&1 && kill -9 "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$path"
  fi
}

status_output() {
  read_state
  state="${STATE:-${state:-}}"
  if [ "${state:-}" = "closed" ]; then
    printf 'status: closed\nprofile_dir: %s\ncdp_port: %s\ncdp_host: 127.0.0.1\n' "${profile_dir:-unknown}" "${cdp_port:-unknown}"
    return
  fi
  local current_pid
  current_pid="$(read_pid browser)"
  if [ -n "$current_pid" ] && kill -0 "$current_pid" >/dev/null 2>&1; then
    state="running"
  else
    state="stopped"
  fi
  printf 'status: %s\nprofile_dir: %s\ncdp_port: %s\ncdp_host: 127.0.0.1\n' "$state" "$profile_dir" "$cdp_port"
}

start() {
  init_run_dir
  browser_cmd="${cli_browser_cmd:-$browser_cmd}"
  cdp_port="${cli_cdp_port:-$cdp_port}"
  display_num="${cli_display_num:-$display_num}"
  origin="${cli_origin:-$origin}"
  session_key="${cli_session_key:-$session_key}"
  profile_dir="${cli_profile_dir:-$profile_dir}"
  initial_url="${cli_url:-$initial_url}"
  mode="${cli_mode:-$mode}"
  if [ -z "$profile_dir" ]; then
    profile_dir="$HOME/.agent-browser/profiles/default"
  fi
  start_browser
  state="running"
  write_state
  printf 'status: running\nprofile_dir: %s\ncdp_port: %s\ncdp_host: 127.0.0.1\n' "$profile_dir" "$cdp_port"
}

stop() {
  init_run_dir
  stop_pid browser
  state="stopped"
  write_state
  echo "status: stopped"
}

list_targets() {
  echo "[]"
}

ensure_browser() {
  init_run_dir
  if [ -n "$(read_pid browser)" ] && kill -0 "$(read_pid browser)" >/dev/null 2>&1; then
    status_output
    return
  fi
  start
}

command="${1:-}"
shift || true

cli_browser_cmd=""
cli_profile_dir=""
cli_origin=""
cli_session_key=""
cli_url=""
cli_cdp_port="19222"
cli_display_num="88"
cli_mode="headless"

run_dir=""
log_dir=""
state_file=""
browser_cmd="sleep 600"
mode="headless"
origin=""
session_key="default"
profile_dir=""
initial_url=""
cdp_port="19222"
display_num="88"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)
      run_dir="$2"
      shift 2
      ;;
    --profile-dir)
      profile_dir="$2"
      cli_profile_dir="$2"
      shift 2
      ;;
    --origin)
      origin="$2"
      cli_origin="$2"
      shift 2
      ;;
    --session-key)
      session_key="$2"
      cli_session_key="$2"
      shift 2
      ;;
    --url)
      initial_url="$2"
      cli_url="$2"
      shift 2
      ;;
    --cdp-port)
      cdp_port="$2"
      cli_cdp_port="$2"
      shift 2
      ;;
    --display)
      display_num="$2"
      cli_display_num="$2"
      shift 2
      ;;
    --browser)
      browser_cmd="$2"
      cli_browser_cmd="$2"
      shift 2
      ;;
    --mode)
      mode="$2"
      cli_mode="$2"
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

case "$command" in
  start)
    start
    ;;
  status)
    init_run_dir
    status_output
    ;;
  stop)
    stop
    ;;
  list-targets)
    list_targets
    ;;
  ensure-browser)
    ensure_browser
    ;;
  *)
    usage
    exit 1
    ;;
esac
