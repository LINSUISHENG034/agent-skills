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

pid_running() {
  local pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

read_pid_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cat "$file"
  fi
}

stop_pid_file() {
  local file="$1"
  local pid
  pid="$(read_pid_file "$file")"
  if pid_running "$pid"; then
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    local attempt
    for attempt in 1 2 3 4 5; do
      if ! pid_running "$pid"; then
        break
      fi
      sleep 1
    done
    if pid_running "$pid"; then
      kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$file"
}

write_closed_state() {
  local run_dir="$1"
  local state_file="$run_dir/runtime.env"
  local tmp_file
  tmp_file="$(mktemp)"

  if [ -f "$state_file" ]; then
    awk '
      BEGIN { wrote=0 }
      /^STATE=/ { print "STATE=closed"; wrote=1; next }
      /^BROWSER_PID=/ { print "BROWSER_PID="; next }
      { print }
      END { if (!wrote) print "STATE=closed" }
    ' "$state_file" >"$tmp_file"
  else
    printf 'STATE=closed\nRUN_DIR=%q\nBROWSER_PID=\n' "$run_dir" >"$tmp_file"
  fi

  mv "$tmp_file" "$state_file"
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

stop_pid_file "$RUN_DIR/browser.pid"
stop_pid_file "$RUN_DIR/xvfb.pid"
stop_pid_file "$RUN_DIR/x11vnc.pid"
stop_pid_file "$RUN_DIR/websockify.pid"
rm -rf "$RUN_DIR/tmp"
write_closed_state "$RUN_DIR"
