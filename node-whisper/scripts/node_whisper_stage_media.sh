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

input_path=""
input_stem=""
output_dir=""
want_json=0
transport="ssh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_path="${2:-}"
      shift 2
      ;;
    --input-stem)
      input_stem="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --want-json)
      want_json=1
      shift
      ;;
    --transport)
      transport="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: node_whisper_stage_media.sh --input <path> --input-stem <name> --output-dir <path> [--want-json] [--transport ssh]
EOF
      exit 0
      ;;
    *)
      fail "stage" "invalid_arguments" "Unknown option: $1" 2
      ;;
  esac
done

[[ -n "$input_path" ]] || fail "stage" "invalid_arguments" "Missing --input." 2
[[ -n "$input_stem" ]] || fail "stage" "invalid_arguments" "Missing --input-stem." 2
[[ -n "$output_dir" ]] || fail "stage" "invalid_arguments" "Missing --output-dir." 2
[[ -n "$REMOTE_USER" ]] || fail "stage" "missing_configuration" "Set NODE_WHISPER_REMOTE_USER in the skill-root .env or the environment." 3
[[ -n "$REMOTE_HOST" ]] || fail "stage" "missing_configuration" "Set NODE_WHISPER_REMOTE_HOST in the skill-root .env or the environment." 3
[[ -n "$SSH_KEY_PATH" ]] || fail "stage" "missing_configuration" "Set NODE_WHISPER_SSH_KEY in the skill-root .env or the environment." 3

if [[ "$transport" != "ssh" ]]; then
  fail "stage" "unsupported_transport" "Only the SSH transport is implemented in this script." 3
fi

job_id="$(date +%Y%m%d-%H%M%S)-$$"
remote_prepare_ps1="C:/Users/${REMOTE_USER}/prepare-node-whisper-job.ps1"
remote_runner="${RUNTIME_DIR}/bin/run-node-whisper-job.ps1"
remote_transcriber="${RUNTIME_DIR}/bin/transcribe_faster_whisper.py"

if ! ssh -o StrictHostKeyChecking=accept-new -i "$SSH_KEY_PATH" \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '${RUNTIME_DIR}' | Out-Null; New-Item -ItemType Directory -Force -Path '${RUNTIME_DIR}/bin' | Out-Null\"" >/dev/null 2>&1; then
  fail "stage" "node_unreachable" "Failed to create runtime directories on ${REMOTE_HOST}." 10
fi

scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
  "$SCRIPT_DIR/prepare-node-whisper-job.ps1" \
  "${REMOTE_USER}@${REMOTE_HOST}:${remote_prepare_ps1}" >/dev/null 2>&1 || \
  fail "stage" "input_stage_failed" "Failed to upload prepare-node-whisper-job.ps1 to ${REMOTE_HOST}." 13

scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
  "$SCRIPT_DIR/run-node-whisper-job.ps1" \
  "${REMOTE_USER}@${REMOTE_HOST}:${remote_runner}" >/dev/null 2>&1 || \
  fail "stage" "input_stage_failed" "Failed to upload run-node-whisper-job.ps1 to ${REMOTE_HOST}." 13

scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
  "$SCRIPT_DIR/transcribe_faster_whisper.py" \
  "${REMOTE_USER}@${REMOTE_HOST}:${remote_transcriber}" >/dev/null 2>&1 || \
  fail "stage" "input_stage_failed" "Failed to upload transcribe_faster_whisper.py to ${REMOTE_HOST}." 13

job_json="$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "powershell -NoProfile -ExecutionPolicy Bypass -File \"$remote_prepare_ps1\" -RuntimeDir \"$RUNTIME_DIR\" -JobId \"$job_id\"" 2>/dev/null)" || \
  fail "stage" "input_stage_failed" "Failed to prepare the remote job directory on ${REMOTE_HOST}." 13

remote_input_path="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["inputPath"])' <<<"$job_json")"
remote_text_out="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["textOut"])' <<<"$job_json")"
remote_json_out="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["jsonOut"])' <<<"$job_json")"

scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
  "$input_path" \
  "${REMOTE_USER}@${REMOTE_HOST}:${remote_input_path}" >/dev/null 2>&1 || \
  fail "stage" "input_stage_failed" "Failed to copy the input media to ${REMOTE_HOST}:${remote_input_path}." 13

"$PYTHON_BIN" - <<'PY' "$job_id" "$RUNTIME_DIR" "$remote_input_path" "$remote_text_out" "$remote_json_out" "$output_dir" "$input_stem" "$want_json"
import json
import sys

job_id, runtime_dir, remote_input_path, remote_text_out, remote_json_out, output_dir, input_stem, want_json = sys.argv[1:]
payload = {
    "ok": True,
    "stage": "stage",
    "job_id": job_id,
    "runtime_dir": runtime_dir,
    "remote_input_path": remote_input_path,
    "remote_text_out": remote_text_out,
    "remote_json_out": remote_json_out,
    "output_dir": output_dir,
    "input_stem": input_stem,
    "want_json": want_json == "1",
}
print(json.dumps(payload, ensure_ascii=False))
PY
