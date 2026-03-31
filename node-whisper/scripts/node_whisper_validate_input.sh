#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./node_whisper_load_env.sh
source "$SCRIPT_DIR/node_whisper_load_env.sh"
PYTHON_BIN="${PYTHON_BIN:-python3}"

usage() {
  cat <<'EOF'
Usage: node_whisper_orchestrate.sh <input_path> [options]

Options:
  --model <name>         Whisper model (default: large-v3)
  --language <code>      Language code (default: auto-detect)
  --json                 Also fetch JSON output
  --timestamps           Include segment timestamps; implies --json
  --quiet                Keep stdout reserved for transcript text
  --node <name>          Preferred OpenClaw node name or id
  --force-repair         Reinstall/repair runtime before transcribing
  --transport <name>     Transport mode: ssh or node-host (default: ssh)
  --output-dir <path>    Local artifact directory (default: input directory)
  --dry-run              Validate and print normalized request JSON
  -h, --help             Show this help
EOF
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

model="large-v3"
language=""
want_json=0
timestamps=0
quiet=0
force_repair=0
dry_run=0
transport="${NODE_WHISPER_TRANSPORT:-ssh}"
node_name="${NODE_WHISPER_NODE_NAME:-}"
output_dir=""
input_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      model="${2:-}"
      shift 2
      ;;
    --language)
      language="${2:-}"
      shift 2
      ;;
    --json)
      want_json=1
      shift
      ;;
    --timestamps)
      timestamps=1
      want_json=1
      shift
      ;;
    --quiet)
      quiet=1
      shift
      ;;
    --node)
      node_name="${2:-}"
      shift 2
      ;;
    --force-repair)
      force_repair=1
      shift
      ;;
    --transport)
      transport="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      fail "input" "invalid_arguments" "Unknown option: $1" 2
      ;;
    *)
      if [[ -n "$input_path" ]]; then
        fail "input" "invalid_arguments" "Only one input media path is supported per run." 2
      fi
      input_path="$1"
      shift
      ;;
  esac
done

if [[ -z "$input_path" ]]; then
  fail "input" "input_not_found" "A local audio or video file path is required." 2
fi

if [[ ! -e "$input_path" ]]; then
  fail "input" "input_not_found" "Input media not found: $input_path" 2
fi

if [[ ! -f "$input_path" ]]; then
  fail "input" "unsupported_input_type" "Input must be a regular file: $input_path" 2
fi

case "$transport" in
  ssh|node-host)
    ;;
  *)
    fail "input" "invalid_arguments" "Unsupported transport: $transport" 2
    ;;
esac

abs_input="$("$PYTHON_BIN" -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$input_path")"
input_name="$(basename "$abs_input")"
input_stem="${input_name%.*}"
input_ext="${input_name##*.}"
input_ext=".${input_ext,,}"

media_kind=""
case "$input_ext" in
  .wav|.mp3|.m4a|.aac|.flac|.ogg|.opus|.wma)
    media_kind="audio"
    ;;
  .mp4|.mkv|.mov|.avi|.m4v|.webm)
    media_kind="video"
    ;;
  *)
    fail "input" "unsupported_input_type" "Unsupported media extension: $input_ext" 2
    ;;
esac

if [[ -z "$output_dir" ]]; then
  output_dir="$(dirname "$abs_input")"
else
  output_dir="$("$PYTHON_BIN" -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$output_dir")"
fi

output_format="text"
if [[ "$want_json" -eq 1 ]]; then
  output_format="text+json"
fi

"$PYTHON_BIN" - <<'PY' "$abs_input" "$input_name" "$input_stem" "$input_ext" "$media_kind" "$output_format" "$model" "$language" "$node_name" "$output_dir" "$transport" "$want_json" "$timestamps" "$quiet" "$force_repair" "$dry_run"
import json
import sys

(
    input_path,
    input_name,
    input_stem,
    input_extension,
    media_kind,
    output_format,
    model,
    language,
    node_name,
    output_dir,
    transport,
    want_json,
    timestamps,
    quiet,
    force_repair,
    dry_run,
) = sys.argv[1:]

payload = {
    "ok": True,
    "stage": "input",
    "input_path": input_path,
    "input_name": input_name,
    "input_stem": input_stem,
    "input_extension": input_extension,
    "media_kind": media_kind,
    "output_format": output_format,
    "model": model,
    "language": language or None,
    "node_name": node_name or None,
    "output_dir": output_dir,
    "transport": transport,
    "want_json": want_json == "1",
    "timestamps": timestamps == "1",
    "quiet": quiet == "1",
    "force_repair": force_repair == "1",
    "dry_run": dry_run == "1",
}
print(json.dumps(payload, ensure_ascii=False))
PY
