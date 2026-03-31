#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./node_whisper_load_env.sh
source "$SCRIPT_DIR/node_whisper_load_env.sh"
PYTHON_BIN="${PYTHON_BIN:-python3}"
REMOTE_USER="${NODE_WHISPER_REMOTE_USER:-}"
REMOTE_HOST="${NODE_WHISPER_REMOTE_HOST:-}"
SSH_KEY_PATH="${NODE_WHISPER_SSH_KEY:-${SSH_KEY:-$HOME/.ssh/node_whisper_win}}"

json_get() {
  local field="$1"
  "$PYTHON_BIN" -c 'import json,sys
data=json.load(sys.stdin)
value=data
for part in sys.argv[1].split("."):
    value=value[part]
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)' "$field"
}

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

validated_json="$("$SCRIPT_DIR/node_whisper_validate_input.sh" "$@" 2> >(cat >&2))" || exit $?

dry_run="$(json_get dry_run <<<"$validated_json")"
if [[ "$dry_run" == "true" ]]; then
  printf '%s\n' "$validated_json"
  exit 0
fi

input_path="$(json_get input_path <<<"$validated_json")"
input_stem="$(json_get input_stem <<<"$validated_json")"
output_dir="$(json_get output_dir <<<"$validated_json")"
transport="$(json_get transport <<<"$validated_json")"
model="$(json_get model <<<"$validated_json")"
language="$(json_get language <<<"$validated_json")"
quiet="$(json_get quiet <<<"$validated_json")"
want_json="$(json_get want_json <<<"$validated_json")"
timestamps="$(json_get timestamps <<<"$validated_json")"
node_name="$(json_get node_name <<<"$validated_json")"
force_repair="$(json_get force_repair <<<"$validated_json")"

[[ -n "$REMOTE_USER" ]] || fail "config" "missing_configuration" "Set NODE_WHISPER_REMOTE_USER in the skill-root .env or the environment." 3
[[ -n "$REMOTE_HOST" ]] || fail "config" "missing_configuration" "Set NODE_WHISPER_REMOTE_HOST in the skill-root .env or the environment." 3
[[ -n "$SSH_KEY_PATH" ]] || fail "config" "missing_configuration" "Set NODE_WHISPER_SSH_KEY in the skill-root .env or the environment." 3

ready_args=(--transport "$transport")
if [[ -n "$node_name" ]]; then
  ready_args+=(--node "$node_name")
fi
if [[ "$force_repair" == "true" ]]; then
  ready_args+=(--force-repair)
fi
if [[ "$quiet" == "true" ]]; then
  ready_args+=(--quiet)
fi

ready_json="$("$SCRIPT_DIR/node_whisper_require_ready.sh" "${ready_args[@]}" 2> >(cat >&2))" || exit $?
remote_host="$(json_get remote_host <<<"$ready_json")"
runtime_dir="$(json_get runtime_dir <<<"$ready_json")"

stage_args=(
  --input "$input_path"
  --input-stem "$input_stem"
  --output-dir "$output_dir"
  --transport "$transport"
)
if [[ "$want_json" == "true" ]]; then
  stage_args+=(--want-json)
fi

stage_json="$("$SCRIPT_DIR/node_whisper_stage_media.sh" "${stage_args[@]}" 2> >(cat >&2))" || exit $?
job_id="$(json_get job_id <<<"$stage_json")"
remote_input_path="$(json_get remote_input_path <<<"$stage_json")"
remote_text_out="$(json_get remote_text_out <<<"$stage_json")"
remote_json_out="$(json_get remote_json_out <<<"$stage_json")"

remote_runner="${runtime_dir}/bin/run-node-whisper-job.ps1"
remote_exec_cmd=(powershell -NoProfile -ExecutionPolicy Bypass -File "$remote_runner" -RuntimeDir "$runtime_dir" -JobId "$job_id" -InputPath "$remote_input_path" -Model "$model")
if [[ -n "$language" ]]; then
  remote_exec_cmd+=(-Language "$language")
fi
if [[ "$want_json" == "true" ]]; then
  remote_exec_cmd+=(-WantJson)
fi
if [[ "$timestamps" == "true" ]]; then
  remote_exec_cmd+=(-Timestamps)
fi

remote_exec_json="$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "${remote_exec_cmd[@]}" 2>/dev/null)" || \
  fail "transcribe" "transcription_failed" "Remote transcription failed on ${remote_host}." 15

remote_ok="$("$PYTHON_BIN" -c 'import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    print("false")
else:
    print("true" if data.get("ok") else "false")' <<<"$remote_exec_json")"
if [[ "$remote_ok" != "true" ]]; then
  fail "transcribe" "transcription_failed" "Remote transcription did not report ok=true on ${remote_host}." 15
fi

fetch_args=(
  --remote-text-out "$remote_text_out"
  --output-dir "$output_dir"
  --input-stem "$input_stem"
)
if [[ "$want_json" == "true" ]]; then
  fetch_args+=(--want-json --remote-json-out "$remote_json_out")
fi

fetch_json="$("$SCRIPT_DIR/node_whisper_fetch_results.sh" "${fetch_args[@]}" 2> >(cat >&2))" || exit $?
local_text_out="$(json_get local_text_out <<<"$fetch_json")"
local_json_out="$(json_get local_json_out <<<"$fetch_json")"

if [[ ! -f "$local_text_out" ]]; then
  fail "fetch" "result_fetch_failed" "Transcript text file was not created: $local_text_out" 14
fi

cat "$local_text_out"

if [[ "$quiet" != "true" ]]; then
  if [[ "$want_json" == "true" ]]; then
    printf 'node-whisper: node=%s model=%s text=%s json=%s\n' "$remote_host" "$model" "$local_text_out" "$local_json_out" >&2
  else
    printf 'node-whisper: node=%s model=%s text=%s\n' "$remote_host" "$model" "$local_text_out" >&2
  fi
fi
