#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./node_whisper_load_env.sh
source "$SCRIPT_DIR/node_whisper_load_env.sh"
PYTHON_BIN="${PYTHON_BIN:-python3}"

REMOTE_USER="${NODE_WHISPER_REMOTE_USER:-}"
REMOTE_HOST="${NODE_WHISPER_REMOTE_HOST:-}"
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

remote_text_out=""
remote_json_out=""
output_dir=""
input_stem=""
want_json=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-text-out)
      remote_text_out="${2:-}"
      shift 2
      ;;
    --remote-json-out)
      remote_json_out="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --input-stem)
      input_stem="${2:-}"
      shift 2
      ;;
    --want-json)
      want_json=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: node_whisper_fetch_results.sh --remote-text-out <path> --output-dir <path> --input-stem <name> [--remote-json-out <path>] [--want-json]
EOF
      exit 0
      ;;
    *)
      fail "fetch" "invalid_arguments" "Unknown option: $1" 2
      ;;
  esac
done

[[ -n "$remote_text_out" ]] || fail "fetch" "invalid_arguments" "Missing --remote-text-out." 2
[[ -n "$output_dir" ]] || fail "fetch" "invalid_arguments" "Missing --output-dir." 2
[[ -n "$input_stem" ]] || fail "fetch" "invalid_arguments" "Missing --input-stem." 2
[[ -n "$REMOTE_USER" ]] || fail "fetch" "missing_configuration" "Set NODE_WHISPER_REMOTE_USER in the skill-root .env or the environment." 3
[[ -n "$REMOTE_HOST" ]] || fail "fetch" "missing_configuration" "Set NODE_WHISPER_REMOTE_HOST in the skill-root .env or the environment." 3
[[ -n "$SSH_KEY_PATH" ]] || fail "fetch" "missing_configuration" "Set NODE_WHISPER_SSH_KEY in the skill-root .env or the environment." 3

mkdir -p "$output_dir"
local_text_out="${output_dir}/${input_stem}.node-whisper.txt"
local_json_out="${output_dir}/${input_stem}.node-whisper.json"

scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}:${remote_text_out}" \
  "$local_text_out" >/dev/null 2>&1 || \
  fail "fetch" "result_fetch_failed" "Failed to fetch transcript text from ${REMOTE_HOST}:${remote_text_out}." 14

if [[ "$want_json" -eq 1 ]]; then
  [[ -n "$remote_json_out" ]] || fail "fetch" "result_fetch_failed" "JSON output was requested but no remote JSON path was provided." 14
  scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
    "${REMOTE_USER}@${REMOTE_HOST}:${remote_json_out}" \
    "$local_json_out" >/dev/null 2>&1 || \
    fail "fetch" "result_fetch_failed" "Failed to fetch transcript JSON from ${REMOTE_HOST}:${remote_json_out}." 14
fi

"$PYTHON_BIN" - <<'PY' "$local_text_out" "$local_json_out" "$want_json"
import json
import sys

local_text_out, local_json_out, want_json = sys.argv[1:]
payload = {
    "ok": True,
    "stage": "fetch",
    "local_text_out": local_text_out,
    "local_json_out": local_json_out if want_json == "1" else None,
}
print(json.dumps(payload, ensure_ascii=False))
PY
