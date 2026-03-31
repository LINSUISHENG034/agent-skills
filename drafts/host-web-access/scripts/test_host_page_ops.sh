#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

output="$("$BASE_DIR/host-page-ops.py" --help 2>&1)"
printf '%s\n' "$output" | grep -q -- '--eval'
printf '%s\n' "$output" | grep -q -- '--navigate'
printf '%s\n' "$output" | grep -q -- '--wait-navigation'
printf '%s\n' "$output" | grep -q -- '--wait-for'
printf '%s\n' "$output" | grep -q -- '--click'
printf '%s\n' "$output" | grep -q -- '--click-link-text'
printf '%s\n' "$output" | grep -q -- '--click-at'
printf '%s\n' "$output" | grep -q -- '--set-files'
printf '%s\n' "$output" | grep -q -- '--set-files-selector'
printf '%s\n' "$output" | grep -q -- '--scroll'
printf '%s\n' "$output" | grep -q -- '--check'
