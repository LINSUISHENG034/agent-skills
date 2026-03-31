#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

output="$("$BASE_DIR/host-page-snapshot.py" --help 2>&1)"
printf '%s\n' "$output" | grep -q -- '--format'
printf '%s\n' "$output" | grep -q -- '--max-chars'
printf '%s\n' "$output" | grep -q -- 'topic-links'
printf '%s\n' "$output" | grep -q -- 'markdown'
printf '%s\n' "$output" | grep -q -- 'text'
printf '%s\n' "$output" | grep -q -- 'links'
