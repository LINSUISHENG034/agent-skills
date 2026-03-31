#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/runtime-common.sh"

usage() {
  cat <<'EOF'
Usage:
  assist-lan-session.sh start --run-dir DIR --origin URL --session-key KEY --profile-dir DIR [options]
  assist-lan-session.sh status --run-dir DIR
  assist-lan-session.sh capture --run-dir DIR --origin URL --session-key KEY --profile-dir DIR [options]
  assist-lan-session.sh stop --run-dir DIR

Options:
  --manifest-root DIR
  --novnc-port PORT
EOF
}

die() {
  printf '[assist-lan-session] ERROR: %s\n' "$*" >&2
  exit 1
}

state_file() {
  printf '%s/state.env\n' "$RUN_DIR"
}

write_state() {
  mkdir -p "$RUN_DIR"
  cat >"$(state_file)" <<EOF
ORIGIN=$ORIGIN
SESSION_KEY=$SESSION_KEY
PROFILE_DIR=$PROFILE_DIR
NOVNC_PORT=$NOVNC_PORT
LAN_HOST=$LAN_HOST
LAN_URL=$LAN_URL
EOF
}

read_state() {
  if [ -f "$(state_file)" ]; then
    # shellcheck disable=SC1090
    source "$(state_file)"
  else
    die "no active assisted session"
  fi
}

command="${1:-}"
[ -n "$command" ] || die "missing command"
shift || true

run_dir=""
origin=""
session_key="default"
profile_dir=""
manifest_root="$HOME/.agent-browser"
novnc_port="6084"
lan_host=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)
      run_dir="$2"
      shift 2
      ;;
    --origin)
      origin="$2"
      shift 2
      ;;
    --session-key)
      session_key="$2"
      shift 2
      ;;
    --profile-dir)
      profile_dir="$2"
      shift 2
      ;;
    --manifest-root)
      manifest_root="$2"
      shift 2
      ;;
    --novnc-port)
      novnc_port="$2"
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

[ -n "$run_dir" ] || die "missing required argument: --run-dir"

RUN_DIR="$run_dir"

if [ -n "$lan_host" ]; then
  LAN_HOST="$lan_host"
else
  LAN_HOST="${AGENT_BROWSER_NOVNC_PUBLIC_HOST:-$(primary_ipv4 || true)}"
fi
[ -n "$LAN_HOST" ] || die "unable to determine LAN host for noVNC"

LAN_URL="$(lan_novnc_url "$LAN_HOST" "$novnc_port")"

state_file_path="$(state_file)"

cmd_start() {
  [ -n "$origin" ] || die "missing --origin"
  [ -n "$profile_dir" ] || die "missing --profile-dir"
  mkdir -p "$run_dir"
  ORIGIN="$origin"
  SESSION_KEY="$session_key"
  PROFILE_DIR="$profile_dir"
  NOVNC_PORT="$novnc_port"
  LAN_HOST="$LAN_HOST"
  LAN_URL="$LAN_URL"
  write_state
  printf 'lan_novnc_url: %s\n' "$LAN_URL"
}

cmd_status() {
  read_state
  printf 'lan_novnc_url: %s\n' "$LAN_URL"
}

cmd_capture() {
  read_state
  manifest_root="${manifest_root:-$HOME/.agent-browser}"
  session_manifest="$("$SCRIPT_DIR/session-manifest.sh" write \
    --root "$manifest_root" \
    --origin "$origin" \
    --session-key "$session_key" \
    --state ready \
    --browser-pid 0 \
    --profile-dir "$profile_dir" \
    --task-scope assisted \
    --account-hint assisted)$(
    printf '' # no-op to capture exit code
  )"
  site_root="${manifest_root}"
  site_key="$(site_key "$origin")"
  "$SCRIPT_DIR/site-session-registry.sh" write \
    --root "$site_root" \
    --site "$site_key" \
    --session-key "$session_key" \
    --profile-dir "$profile_dir" \
    --source-origin "$origin" >/dev/null
  printf 'lan_novnc_url: %s\n' "$LAN_URL"
}

cmd_stop() {
  rm -f "$state_file_path"
  printf 'lan_novnc_url: %s\n' "$LAN_URL"
}

case "$command" in
  start)
    cmd_start
    ;;
  status)
    cmd_status
    ;;
  capture)
    cmd_capture
    ;;
  stop)
    cmd_stop
    ;;
  *)
    usage
    exit 1
    ;;
esac
