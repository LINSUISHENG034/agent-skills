#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./node_whisper_load_env.sh
source "$SCRIPT_DIR/node_whisper_load_env.sh"
PYTHON_BIN="${PYTHON_BIN:-python3}"
HTTP_PROVIDER_HELPER="${NODE_WHISPER_FALLBACK_HTTP_HELPER:-$SCRIPT_DIR/node_whisper_fallback_provider_http.py}"

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

provider=""
input_path=""
input_stem=""
output_dir=""
model="large-v3"
language=""
config_path=""
want_json=0
timestamps=0
reason_stage=""
reason_code=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      provider="${2:-}"
      shift 2
      ;;
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
    --model)
      model="${2:-}"
      shift 2
      ;;
    --language)
      language="${2:-}"
      shift 2
      ;;
    --config)
      config_path="${2:-}"
      shift 2
      ;;
    --want-json)
      want_json=1
      shift
      ;;
    --timestamps)
      timestamps=1
      want_json=1
      shift
      ;;
    --reason-stage)
      reason_stage="${2:-}"
      shift 2
      ;;
    --reason-code)
      reason_code="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: node_whisper_fallback.sh --provider <name> --input <path> --input-stem <name> --output-dir <path> [options]
EOF
      exit 0
      ;;
    *)
      fail "fallback" "invalid_arguments" "Unknown option: $1" 2
      ;;
  esac
done

[[ -n "$provider" ]] || fail "fallback" "invalid_arguments" "Missing --provider." 2
[[ -n "$input_path" ]] || fail "fallback" "invalid_arguments" "Missing --input." 2
[[ -n "$input_stem" ]] || fail "fallback" "invalid_arguments" "Missing --input-stem." 2
[[ -n "$output_dir" ]] || fail "fallback" "invalid_arguments" "Missing --output-dir." 2
[[ -f "$input_path" ]] || fail "fallback" "input_not_found" "Fallback input media not found: $input_path" 2

case "$provider" in
  http-generic)
    provider_args=(
      --provider "$provider"
      --input "$input_path"
      --input-stem "$input_stem"
      --output-dir "$output_dir"
      --model "$model"
    )
    if [[ -n "$language" ]]; then
      provider_args+=(--language "$language")
    fi
    if [[ -n "$config_path" ]]; then
      provider_args+=(--config "$config_path")
    fi
    if [[ "$want_json" -eq 1 ]]; then
      provider_args+=(--want-json)
    fi
    if [[ "$timestamps" -eq 1 ]]; then
      provider_args+=(--timestamps)
    fi
    if [[ -n "$reason_stage" ]]; then
      provider_args+=(--reason-stage "$reason_stage")
    fi
    if [[ -n "$reason_code" ]]; then
      provider_args+=(--reason-code "$reason_code")
    fi
    "$PYTHON_BIN" "$HTTP_PROVIDER_HELPER" "${provider_args[@]}"
    ;;
  *)
    fail "fallback" "unsupported_fallback_provider" "Unsupported fallback provider: $provider" 2
    ;;
esac
