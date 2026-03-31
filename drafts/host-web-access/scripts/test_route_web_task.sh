#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="$BASE_DIR/route-web-task.sh"

run_expect() {
  local expected_route="$1"
  local expected_reason="$2"
  shift 2
  local output
  output="$("$CMD" "$@")"
  python3 - "$output" <<PY
import json, sys
data = json.loads(sys.argv[1])
assert data.get("route") == "$expected_route"
assert data.get("reason") == "$expected_reason"
assert isinstance(data.get("needs_browser"), bool)
PY
}

run_expect search latest-info --latest
run_expect fetch public-article --article
run_expect browser dynamic-rendering --dynamic
run_expect browser protected-site --protected
run_expect browser interaction-required --interactive
run_expect browser host-browser-requested --host-browser
