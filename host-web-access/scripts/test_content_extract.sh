#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$BASE_DIR/content-extract.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

content = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "dt.UTC" not in content, "use datetime.timezone.utc for Python 3.10 compatibility"
assert "datetime.UTC" not in content, "use datetime.timezone.utc for Python 3.10 compatibility"
PY

cat >"$TMP_DIR/article.html" <<'HTML'
<!doctype html>
<html>
  <head><title>Local Article</title></head>
  <body>
    <article>
      <h1>Local Article</h1>
      <p>This local article is long enough to exercise extraction and timestamp rendering without network access.</p>
    </article>
  </body>
</html>
HTML

output="$("$TARGET" --url "file://$TMP_DIR/article.html" --output-dir "$TMP_DIR/out")"

python3 - "$output" "$TMP_DIR/out" <<'PY'
import datetime as dt
import json
from pathlib import Path
import sys

payload = json.loads(sys.argv[1])
output_dir = Path(sys.argv[2])

assert payload["title"] == "Local Article", payload
assert payload["url"].startswith("file://"), payload
assert payload["extraction_method"] == "http-html", payload
assert payload["fetched_at"].endswith("Z"), payload
dt.datetime.fromisoformat(payload["fetched_at"].replace("Z", "+00:00"))
saved_path = Path(payload["saved_path"])
assert saved_path.is_file(), payload
assert saved_path.parent == output_dir, payload
PY
