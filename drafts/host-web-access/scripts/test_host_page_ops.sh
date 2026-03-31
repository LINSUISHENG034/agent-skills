#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$BASE_DIR/host-page-ops.py"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

content = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "ubuntu-browser-session" not in content, content
assert "parents[5]" not in content, content
PY

output="$("$TARGET" --help 2>&1)"
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
