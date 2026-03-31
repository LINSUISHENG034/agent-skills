#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./node_whisper_load_env.sh
source "$SCRIPT_DIR/node_whisper_load_env.sh"
PYTHON_BIN="${PYTHON_BIN:-python3}"

REMOTE_USER="${NODE_WHISPER_REMOTE_USER:-}"
REMOTE_HOST="${NODE_WHISPER_REMOTE_HOST:-}"
RUNTIME_DIR="${NODE_WHISPER_RUNTIME_DIR:-E:/Projects/node-whisper-runtime}"
SSH_KEY_PATH="${NODE_WHISPER_SSH_KEY:-${SSH_KEY:-$HOME/.ssh/node_whisper_win}}"

fail() {
  local stage="$1"
  local error_code="$2"
  local message="$3"
  local exit_code="${4:-1}"
  "$PYTHON_BIN" "$SCRIPT_DIR/node_whisper_error_map.py" \
    --stage "$stage" \
    --error-code "$error_code" \
    --message "$message" \
    --exit-code "$exit_code" >&2
  exit "$exit_code"
}

transport="ssh"
node_name=""
force_repair=0
quiet=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transport)
      transport="${2:-}"
      shift 2
      ;;
    --node)
      node_name="${2:-}"
      shift 2
      ;;
    --force-repair)
      force_repair=1
      shift
      ;;
    --quiet)
      quiet=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: node_whisper_require_ready.sh [--transport ssh|node-host] [--node name] [--force-repair] [--quiet]
EOF
      exit 0
      ;;
    *)
      fail "ready" "invalid_arguments" "Unknown option: $1" 2
      ;;
  esac
done

case "$transport" in
  ssh)
    ;;
  node-host)
    fail "ready" "unsupported_transport" "As of March 31, 2026, this draft only automates Windows execution through the SSH maintenance path. OpenClaw node-host exec integration is documented but not yet wired into these scripts." 3
    ;;
  *)
    fail "ready" "unsupported_transport" "Unsupported transport: $transport" 2
    ;;
esac

for cmd in ssh scp "$PYTHON_BIN"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "ready" "missing_local_dependency" "Required local command not found: $cmd" 3
  fi
done

[[ -n "$REMOTE_USER" ]] || fail "ready" "missing_configuration" "Set NODE_WHISPER_REMOTE_USER in the skill-root .env or the environment." 3
[[ -n "$REMOTE_HOST" ]] || fail "ready" "missing_configuration" "Set NODE_WHISPER_REMOTE_HOST in the skill-root .env or the environment." 3
[[ -n "$SSH_KEY_PATH" ]] || fail "ready" "missing_configuration" "Set NODE_WHISPER_SSH_KEY in the skill-root .env or the environment." 3

probe_output=""
if ! probe_output="$("$SCRIPT_DIR/run-node-whisper-env-probe.sh" "$REMOTE_USER" "$REMOTE_HOST" 2>/dev/null)"; then
  fail "ready" "node_unreachable" "Failed to probe the Windows node over SSH. Check SSH reachability and credentials for ${REMOTE_USER}@${REMOTE_HOST}." 10
fi

probe_gate="$("$PYTHON_BIN" -c 'import json,sys
data = json.load(sys.stdin)
commands = data.get("commands", {})
python_ok = commands.get("python", {}).get("available") or commands.get("py", {}).get("available")
failures = []
if not commands.get("uv", {}).get("available"):
    failures.append("uv")
if not commands.get("ffmpeg", {}).get("available"):
    failures.append("ffmpeg")
if not commands.get("nvidiaSmi", {}).get("available"):
    failures.append("nvidia-smi")
if not python_ok:
    failures.append("python/py")
payload = {"ok": not failures, "missing": failures}
print(json.dumps(payload))' <<<"$probe_output")"

probe_ok="$("$PYTHON_BIN" -c 'import json,sys; print("true" if json.load(sys.stdin)["ok"] else "false")' <<<"$probe_gate")"
if [[ "$probe_ok" != "true" ]]; then
  missing="$("$PYTHON_BIN" -c 'import json,sys; print(", ".join(json.load(sys.stdin)["missing"]))' <<<"$probe_gate")"
  fail "ready" "node_runtime_repair_failed" "Remote prerequisite(s) missing on ${REMOTE_HOST}: ${missing}" 11
fi

runtime_repaired=0
smoke_output=""
if [[ "$force_repair" -eq 0 ]]; then
  smoke_output="$("$SCRIPT_DIR/run-node-whisper-smoke.sh" "$REMOTE_USER" "$REMOTE_HOST" 2>/dev/null || true)"
fi

smoke_ok="false"
if [[ -n "$smoke_output" ]]; then
  smoke_ok="$("$PYTHON_BIN" -c 'import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    print("false")
else:
    print("true" if data.get("ok") else "false")' <<<"$smoke_output")"
fi

if [[ "$force_repair" -eq 1 || "$smoke_ok" != "true" ]]; then
  if ! "$SCRIPT_DIR/run-node-whisper-install.sh" "$REMOTE_USER" "$REMOTE_HOST" >/dev/null 2>&1; then
    fail "ready" "node_runtime_repair_failed" "Failed to install or repair faster-whisper on ${REMOTE_HOST}." 12
  fi
  if ! smoke_output="$("$SCRIPT_DIR/run-node-whisper-smoke.sh" "$REMOTE_USER" "$REMOTE_HOST" 2>/dev/null)"; then
    fail "ready" "node_runtime_repair_failed" "The remote smoke test failed after attempting repair on ${REMOTE_HOST}." 12
  fi
  smoke_ok="$("$PYTHON_BIN" -c 'import json,sys; print("true" if json.load(sys.stdin).get("ok") else "false")' <<<"$smoke_output")"
  if [[ "$smoke_ok" != "true" ]]; then
    fail "ready" "node_runtime_repair_failed" "The remote smoke test did not report ok=true after repair on ${REMOTE_HOST}." 12
  fi
  runtime_repaired=1
fi

"$PYTHON_BIN" - <<'PY' "$transport" "$node_name" "$REMOTE_USER" "$REMOTE_HOST" "$RUNTIME_DIR" "$runtime_repaired"
import json
import sys

transport, node_name, remote_user, remote_host, runtime_dir, runtime_repaired = sys.argv[1:]
payload = {
    "ok": True,
    "stage": "ready",
    "transport": transport,
    "node_name": node_name or None,
    "remote_user": remote_user,
    "remote_host": remote_host,
    "runtime_dir": runtime_dir,
    "runtime_repaired": runtime_repaired == "1",
}
print(json.dumps(payload, ensure_ascii=False))
PY
