#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$BASE_DIR/host-page-snapshot.py"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

content = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "ubuntu-browser-session" not in content, content
assert "parents[5]" not in content, content
PY

output="$("$TARGET" --help 2>&1)"
printf '%s\n' "$output" | grep -q -- '--format'
printf '%s\n' "$output" | grep -q -- '--max-chars'
printf '%s\n' "$output" | grep -q -- 'topic-links'
printf '%s\n' "$output" | grep -q -- 'markdown'
printf '%s\n' "$output" | grep -q -- 'text'
printf '%s\n' "$output" | grep -q -- 'links'
