#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  cleanup-host-runtime.sh --run-dir DIR
EOF
}

die() {
  printf '[cleanup-host-runtime] ERROR: %s\n' "$*" >&2
  exit 1
}

pid_file() {
  printf '%s/%s.pid\n' "$RUN_DIR" "$1"
}

pid_running() {
  local pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

stop_pid() {
  local key="$1"
  local path pid
  path="$(pid_file "$key")"
  if [ -f "$path" ]; then
    pid="$(cat "$path")"
    if pid_running "$pid"; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 0.5
      pid_running "$pid" && kill -9 "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$path"
  fi
}

mark_closed() {
  local state_file="$RUN_DIR/runtime.env"
  if [ -f "$state_file" ]; then
    awk 'BEGIN {closed=0} /^STATE=/ {print "STATE=closed"; closed=1; next} /^state=/ {print "state=closed"; closed=1; next} {print} END {if (!closed) print "STATE=closed\nstate=closed"}' "$state_file" >"$state_file.tmp"
    mv "$state_file.tmp" "$state_file"
  else
    printf 'STATE=closed\nstate=closed\nRUN_DIR=%s\n' "$RUN_DIR" >"$state_file"
  fi
}

RUN_DIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
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

[ -n "$RUN_DIR" ] || die "missing required argument: --run-dir"
mkdir -p "$RUN_DIR"

stop_pid browser
stop_pid xvfb
stop_pid x11vnc
stop_pid websockify
rm -rf "$RUN_DIR/tmp" "$RUN_DIR/logs"
mark_closed
