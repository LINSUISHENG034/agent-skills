#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 -m http.server 5900 --bind 127.0.0.1 >/dev/null 2>&1 &
PORT_A_PID=$!
python3 -m http.server 6080 --bind 127.0.0.1 >/dev/null 2>&1 &
PORT_B_PID=$!
trap 'kill "$PORT_A_PID" "$PORT_B_PID" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/x11"
touch "$TMP_DIR/x11/X88"

# shellcheck disable=SC1091
source "$BASE_DIR/runtime-common.sh"

slug="$(origin_slug 'https://foxcode.rjj.cc')"
[ "$slug" = "https___foxcode_rjj_cc" ]
[ "$(derive_origin 'https://foxcode.rjj.cc/api-keys')" = "https://foxcode.rjj.cc" ]

vnc_port="$(pick_free_tcp_port 5900)"
novnc_port="$(pick_free_tcp_port 6080)"
display_num="$(AGENT_BROWSER_X11_SOCKET_DIR="$TMP_DIR/x11" pick_free_display 88)"

[ "$vnc_port" != "5900" ]
[ "$novnc_port" != "6080" ]
[ "$display_num" != "88" ]
