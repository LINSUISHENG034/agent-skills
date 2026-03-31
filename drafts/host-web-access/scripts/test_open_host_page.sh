#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$(mktemp -d)"
LOG="$LOG_DIR/actions.log"

setup_stubs() {
  local tmp="$1"
  rm -f "$LOG"
  mkdir -p "$tmp/bin"
  cat >"$tmp/bin/route-web-task.sh" <<'EOF'
#!/usr/bin/env bash
LOG="${LOG_FILE}"
echo "route:$1" >> "$LOG"
case "$1" in
  --latest) echo '{"route":"search","reason":"latest-info","needs_browser":false}' ;;
  --article) echo '{"route":"fetch","reason":"public-article","needs_browser":false}' ;;
  --interactive) echo '{"route":"browser","reason":"interaction-required","needs_browser":true}' ;;
  --protected) echo '{"route":"browser","reason":"protected-site","needs_browser":true}' ;;
  --dynamic) echo '{"route":"browser","reason":"dynamic-rendering","needs_browser":true}' ;;
  --login-required) echo '{"route":"browser","reason":"login-required","needs_browser":true}' ;;
  --host-browser) echo '{"route":"browser","reason":"host-browser-requested","needs_browser":true}' ;;
  *) echo '{"route":"extract","reason":"default","needs_browser":false}' ;;
esac
EOF
  chmod +x "$tmp/bin/route-web-task.sh"
  cat >"$tmp/bin/browser-runtime.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${LOG_FILE}"
echo "runtime:$1" >> "$LOG"
case "$1" in
  start) exit 0 ;;
  ensure-browser) exit 0 ;;
  status)
    printf 'status: %s\n' "${RUNTIME_STATUS_RESPONSE:-running}"
    ;;
  stop) exit 0 ;;
  list-targets) echo "[]" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/browser-runtime.sh"
  cat >"$tmp/bin/assist-lan-session.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${LOG_FILE}"
echo "assist:$1" >> "$LOG"
if [ "$1" = "capture" ]; then
  mkdir -p "$MANIFEST_ROOT/sessions"
  echo '{"captured": true}' >"$MANIFEST_ROOT/sessions/manual.json"
fi
EOF
  chmod +x "$tmp/bin/assist-lan-session.sh"
  cat >"$tmp/bin/cleanup-host-runtime.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${LOG_FILE}"
echo "cleanup" >> "$LOG"
EOF
  chmod +x "$tmp/bin/cleanup-host-runtime.sh"
  export HOST_WEB_ACCESS_ROUTE_HELPER="$tmp/bin/route-web-task.sh"
  export HOST_WEB_ACCESS_BROWSER_RUNTIME_HELPER="$tmp/bin/browser-runtime.sh"
  export HOST_WEB_ACCESS_ASSIST_HELPER="$tmp/bin/assist-lan-session.sh"
  export HOST_WEB_ACCESS_CLEANUP_HELPER="$tmp/bin/cleanup-host-runtime.sh"
}

run_lightweight() {
  local tmp="$1"
  setup_stubs "$tmp"
  LOG_FILE="${tmp}/actions.log" MANIFEST_ROOT="${tmp}/manifests" \
    bash "$BASE_DIR/open-host-page.sh" --url "https://public" --task-mode latest --expected-action lightweight
  grep -q 'route:--latest' "${tmp}/actions.log"
  ! grep -q 'runtime:start' "${tmp}/actions.log"
}

run_browser_path() {
  local tmp="$1"
  setup_stubs "$tmp"
  LOG_FILE="${tmp}/actions.log" MANIFEST_ROOT="${tmp}/manifests" RUNTIME_STATUS_RESPONSE=stopped \
    bash "$BASE_DIR/open-host-page.sh" --url "https://protected" --task-mode interactive --expected-action browser
  local log="${tmp}/actions.log"
  grep -q 'route:--interactive' "$log"
  grep -q 'runtime:start' "$log"
  grep -q 'runtime:ensure-browser' "$log"
  grep -q 'assist:start' "$log"
  grep -q 'assist:capture' "$log"
  grep -q 'assist:stop' "$log"
  grep -q 'cleanup' "$log"
  test -f "${tmp}/manifests/sessions/manual.json"
}

run_expected_failure() {
  set +e
  bash "$BASE_DIR/open-host-page.sh" >/dev/null 2>&1
  local status=$?
  set -e
  [ "$status" -ne 0 ]
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_expected_failure
run_lightweight "$TMP/light"
run_browser_path "$TMP/browser"
