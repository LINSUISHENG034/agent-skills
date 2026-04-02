#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./node_whisper_load_env.sh
source "$SCRIPT_DIR/node_whisper_load_env.sh"
PYTHON_BIN="${PYTHON_BIN:-python3}"
REMOTE_USER="${NODE_WHISPER_REMOTE_USER:-}"
REMOTE_HOST="${NODE_WHISPER_REMOTE_HOST:-}"
SSH_KEY_PATH="${NODE_WHISPER_SSH_KEY:-${SSH_KEY:-$HOME/.ssh/node_whisper_win}}"
VALIDATE_INPUT_HELPER="${NODE_WHISPER_VALIDATE_INPUT_HELPER:-$SCRIPT_DIR/node_whisper_validate_input.sh}"
REQUIRE_READY_HELPER="${NODE_WHISPER_REQUIRE_READY_HELPER:-$SCRIPT_DIR/node_whisper_require_ready.sh}"
STAGE_MEDIA_HELPER="${NODE_WHISPER_STAGE_MEDIA_HELPER:-$SCRIPT_DIR/node_whisper_stage_media.sh}"
FETCH_RESULTS_HELPER="${NODE_WHISPER_FETCH_RESULTS_HELPER:-$SCRIPT_DIR/node_whisper_fetch_results.sh}"
ERROR_MAP_HELPER="${NODE_WHISPER_ERROR_MAP_HELPER:-$SCRIPT_DIR/node_whisper_error_map.py}"
FALLBACK_HELPER="${NODE_WHISPER_FALLBACK_HELPER:-$SCRIPT_DIR/node_whisper_fallback.sh}"

quiet_requested_from_args() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--quiet" ]]; then
      printf 'true'
      return 0
    fi
  done
  printf 'false'
}

PROGRESS_ENABLED="$(quiet_requested_from_args "$@")"
if [[ "$PROGRESS_ENABLED" == "true" ]]; then
  PROGRESS_ENABLED="false"
else
  PROGRESS_ENABLED="true"
fi

progress() {
  local stage="$1"
  local message="$2"
  if [[ "$PROGRESS_ENABLED" != "true" ]]; then
    return 0
  fi
  printf 'node-whisper[%s]: %s\n' "$stage" "$message" >&2
}

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

json_get_optional() {
  local field="$1"
  "$PYTHON_BIN" -c 'import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit(0)
value=data.get(sys.argv[1], "")
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)' "$field"
}

fallback_is_eligible() {
  local stage="$1"
  local error_code="$2"
  if [[ "$stage" != "ready" ]]; then
    return 1
  fi
  case "$error_code" in
    node_unreachable|node_runtime_repair_failed)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

fail() {
  local stage="$1"
  local error_code="$2"
  local message="$3"
  local exit_code="${4:-1}"
  "$PYTHON_BIN" "$ERROR_MAP_HELPER" \
    --stage "$stage" \
    --error-code "$error_code" \
    --message "$message" \
    --exit-code "$exit_code" >&2
  exit "$exit_code"
}

run_fallback() {
  local trigger_stage="$1"
  local trigger_code="$2"
  local fallback_args fallback_json fallback_text_out fallback_json_out
  progress fallback "using provider ${fallback_provider} after ${trigger_stage}/${trigger_code}"

  fallback_args=(
    --provider "$fallback_provider"
    --input "$input_path"
    --input-stem "$input_stem"
    --output-dir "$output_dir"
    --model "$model"
    --reason-stage "$trigger_stage"
    --reason-code "$trigger_code"
  )
  if [[ -n "$language" ]]; then
    fallback_args+=(--language "$language")
  fi
  if [[ -n "$fallback_config" ]]; then
    fallback_args+=(--config "$fallback_config")
  fi
  if [[ "$want_json" == "true" ]]; then
    fallback_args+=(--want-json)
  fi
  if [[ "$timestamps" == "true" ]]; then
    fallback_args+=(--timestamps)
  fi

  fallback_json="$("$FALLBACK_HELPER" "${fallback_args[@]}" 2> >(cat >&2))" || exit $?
  fallback_text_out="$(json_get_optional local_text_out <<<"$fallback_json")"
  fallback_json_out="$(json_get_optional local_json_out <<<"$fallback_json")"

  if [[ ! -f "$fallback_text_out" ]]; then
    fail "fallback" "result_fetch_failed" "Fallback transcript text file was not created: $fallback_text_out" 14
  fi

  cat "$fallback_text_out"

  if [[ "$quiet" != "true" ]]; then
    if [[ -n "$fallback_json_out" ]]; then
      printf 'node-whisper: engine=fallback:%s text=%s json=%s\n' "$fallback_provider" "$fallback_text_out" "$fallback_json_out" >&2
    else
      printf 'node-whisper: engine=fallback:%s text=%s\n' "$fallback_provider" "$fallback_text_out" >&2
    fi
  fi
  exit 0
}

validated_json="$("$VALIDATE_INPUT_HELPER" "$@" 2> >(cat >&2))" || exit $?

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
fallback_provider="$(json_get_optional fallback_provider <<<"$validated_json")"
fallback_config="$(json_get_optional fallback_config <<<"$validated_json")"
if [[ "$quiet" == "true" ]]; then
  PROGRESS_ENABLED="false"
else
  PROGRESS_ENABLED="true"
fi
progress validate "validated input"

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

progress ready "checking remote runtime"
ready_stderr="$(mktemp)"
if ready_json="$("$REQUIRE_READY_HELPER" "${ready_args[@]}" 2>"$ready_stderr")"; then
  rm -f "$ready_stderr"
else
  ready_status=$?
  ready_error="$(cat "$ready_stderr")"
  rm -f "$ready_stderr"
  ready_stage="$(json_get_optional stage <<<"$ready_error")"
  ready_code="$(json_get_optional error_code <<<"$ready_error")"
  ready_message="$(json_get_optional message <<<"$ready_error")"
  if [[ -n "$fallback_provider" ]] && fallback_is_eligible "$ready_stage" "$ready_code"; then
    printf '%s\n' "$ready_error" >&2
    run_fallback "$ready_stage" "$ready_code"
  fi
  if [[ -n "$ready_stage" && -n "$ready_code" && -n "$ready_message" ]]; then
    if [[ -z "$fallback_provider" ]]; then
      fail "$ready_stage" "$ready_code" "${ready_message} No fallback provider was enabled." "$ready_status"
    fi
    fail "$ready_stage" "$ready_code" "${ready_message} Fallback provider '${fallback_provider}' was not used because this failure is not eligible for fallback." "$ready_status"
  fi
  printf '%s\n' "$ready_error" >&2
  exit "$ready_status"
fi
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

progress stage "staging media on ${remote_host}"
stage_json="$("$STAGE_MEDIA_HELPER" "${stage_args[@]}" 2> >(cat >&2))" || exit $?
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

progress transcribe "running remote transcription on ${remote_host}"
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

progress fetch "fetching results from ${remote_host}"
fetch_json="$("$FETCH_RESULTS_HELPER" "${fetch_args[@]}" 2> >(cat >&2))" || exit $?
local_text_out="$(json_get local_text_out <<<"$fetch_json")"
local_json_out="$(json_get local_json_out <<<"$fetch_json")"

if [[ ! -f "$local_text_out" ]]; then
  fail "fetch" "result_fetch_failed" "Transcript text file was not created: $local_text_out" 14
fi

cat "$local_text_out"

if [[ "$quiet" != "true" ]]; then
  if [[ "$want_json" == "true" ]]; then
    printf 'node-whisper: engine=node-whisper-remote node=%s model=%s text=%s json=%s\n' "$remote_host" "$model" "$local_text_out" "$local_json_out" >&2
  else
    printf 'node-whisper: engine=node-whisper-remote node=%s model=%s text=%s\n' "$remote_host" "$model" "$local_text_out" >&2
  fi
fi
