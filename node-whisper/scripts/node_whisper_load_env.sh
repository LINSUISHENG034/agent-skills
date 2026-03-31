#!/usr/bin/env bash

node_whisper_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_WHISPER_SKILL_ROOT="${NODE_WHISPER_SKILL_ROOT:-$(cd "$node_whisper_script_dir/.." && pwd)}"
NODE_WHISPER_ENV_FILE="${NODE_WHISPER_ENV_FILE:-$NODE_WHISPER_SKILL_ROOT/.env}"

node_whisper_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

node_whisper_strip_matching_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s' "$value"
}

node_whisper_load_env() {
  local env_file="${1:-$NODE_WHISPER_ENV_FILE}"
  [[ -f "$env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(node_whisper_trim "$line")"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" == *=* ]] || continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="$(node_whisper_trim "$key")"
    value="$(node_whisper_trim "$value")"
    value="$(node_whisper_strip_matching_quotes "$value")"

    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ -z "${!key+x}" ]]; then
      export "$key=$value"
    fi
  done <"$env_file"
}

node_whisper_load_env
