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

python3 - "$BASE_DIR" <<'PY'
import importlib.util
import json
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path
import sys


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reserve_port() -> int:
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = int(sock.getsockname()[1])
    sock.close()
    return port


def wait_for_targets(port: int) -> list[dict]:
    for _ in range(100):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=0.5) as response:
                payload = json.loads(response.read().decode("utf-8"))
            if isinstance(payload, list) and payload:
                return payload
        except Exception:
            pass
        time.sleep(0.1)
    raise RuntimeError("CDP target list was not ready")


def run_topic_links_snapshot(html: str, script_dir: Path) -> list[dict]:
    hps = load_module(script_dir / "host-page-snapshot.py", "host_page_snapshot")
    cdp = load_module(script_dir / "host-cdp-core.py", "host_cdp_core")

    port = reserve_port()
    profile_dir = tempfile.mkdtemp(prefix="host-page-snapshot-test-")
    chrome_bin = None
    for candidate in ("google-chrome", "chromium", "chromium-browser"):
        if shutil.which(candidate):
            chrome_bin = candidate
            break
    if chrome_bin is None:
        raise RuntimeError("no supported Chrome/Chromium binary found")
    data_url = "data:text/html;charset=utf-8," + urllib.parse.quote(html)
    chrome_cmd = [
        chrome_bin,
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        f"--remote-debugging-port={port}",
        f"--user-data-dir={profile_dir}",
        data_url,
    ]
    proc = subprocess.Popen(chrome_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        targets = wait_for_targets(port)
        target_id = None
        for target in targets:
            if target.get("type") == "page" and str(target.get("url", "")).startswith("data:text/html"):
                target_id = str(target["id"])
                break
        if target_id is None:
            for target in targets:
                if target.get("type") == "page":
                    target_id = str(target["id"])
                    break
        if target_id is None:
            raise RuntimeError("no page target available")

        value = cdp.evaluate(port, target_id, hps.FORMAT_JS["topic-links"], retry_count=8, retry_delay_ms=120)
        if not isinstance(value, dict):
            raise AssertionError(f"unexpected evaluate payload: {value!r}")
        content = value.get("content", "[]")
        parsed = json.loads(content)
        if not isinstance(parsed, list):
            raise AssertionError(f"topic-links content is not a list: {parsed!r}")
        return parsed
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        shutil.rmtree(profile_dir, ignore_errors=True)


script_dir = Path(sys.argv[1])

# Case 1: repeated container preference + best-anchor scoring + dedupe + no page-wide dump.
case_one_html = """
<!doctype html>
<html>
  <body>
    <nav>
      <a href="https://forum.example.com/home">Home</a>
      <a href="https://forum.example.com/help">Help</a>
    </nav>
    <main>
      <section data-topic-id="a1">
        <h2><a class="topic title" href="https://forum.example.com/t/alpha">Alpha topic</a></h2>
        <a href="https://forum.example.com/u/alice">alice</a>
        <p>alpha meta line</p>
      </section>
      <section data-topic-id="b2">
        <a href="https://forum.example.com/u/bob">bob</a>
        <h3><a class="result headline" href="https://forum.example.com/discussion/beta">Beta discussion title</a></h3>
        <a href="https://forum.example.com/share/beta">share</a>
      </section>
      <section data-topic-id="dup">
        <h2><a class="topic title" href="https://forum.example.com/discussion/beta">Duplicate beta title</a></h2>
      </section>
    </main>
    <footer>
      <a href="https://forum.example.com/privacy">Privacy</a>
    </footer>
  </body>
</html>
"""
case_one_results = run_topic_links_snapshot(case_one_html, script_dir)
case_one_hrefs = [item.get("href") for item in case_one_results]
assert "https://forum.example.com/t/alpha" in case_one_hrefs, case_one_results
assert "https://forum.example.com/discussion/beta" in case_one_hrefs, case_one_results
assert case_one_hrefs.count("https://forum.example.com/discussion/beta") == 1, case_one_results
assert "https://forum.example.com/home" not in case_one_hrefs, case_one_results
assert "https://forum.example.com/help" not in case_one_hrefs, case_one_results
assert "https://forum.example.com/privacy" not in case_one_hrefs, case_one_results

beta = next((item for item in case_one_results if item.get("href") == "https://forum.example.com/discussion/beta"), None)
assert beta is not None, case_one_results
assert beta.get("text") == "Beta discussion title", case_one_results
assert "meta" in beta, case_one_results

# Case 2: fallback scoping must stay inside role=main and not dump links from body-wide nav/footer.
case_two_html = """
<!doctype html>
<html>
  <body>
    <nav><a href="https://forum.example.com/nav-only">Nav only</a></nav>
    <div role="main">
      <section>
        <h2><a href="https://forum.example.com/questions/only-main-result">Only main result</a></h2>
      </section>
    </div>
    <footer><a href="https://forum.example.com/footer-only">Footer only</a></footer>
  </body>
</html>
"""
case_two_results = run_topic_links_snapshot(case_two_html, script_dir)
case_two_hrefs = [item.get("href") for item in case_two_results]
assert case_two_hrefs == ["https://forum.example.com/questions/only-main-result"], case_two_results

# Case 3: multiple sibling article cards should all be used as fallback roots.
case_three_html = """
<!doctype html>
<html>
  <body>
    <article>
      <h2><a href="https://forum.example.com/t/first-article-topic">First article topic</a></h2>
    </article>
    <article>
      <h2><a href="https://forum.example.com/t/second-article-topic">Second article topic</a></h2>
    </article>
    <footer><a href="https://forum.example.com/site-map">Site map</a></footer>
  </body>
</html>
"""
case_three_results = run_topic_links_snapshot(case_three_html, script_dir)
case_three_hrefs = [item.get("href") for item in case_three_results]
assert "https://forum.example.com/t/first-article-topic" in case_three_hrefs, case_three_results
assert "https://forum.example.com/t/second-article-topic" in case_three_hrefs, case_three_results
assert "https://forum.example.com/site-map" not in case_three_hrefs, case_three_results

# Case 4: nested repeated result containers should be detected (main > ul > li).
case_four_html = """
<!doctype html>
<html>
  <body>
    <main>
      <section class="results">
        <ul>
          <li>
            <a href="https://forum.example.com/u/author-one">author-one</a>
            <h2><a class="topic title" href="https://forum.example.com/t/nested-one">Nested one</a></h2>
          </li>
          <li>
            <a href="https://forum.example.com/u/author-two">author-two</a>
            <h2><a class="topic title" href="https://forum.example.com/t/nested-two">Nested two</a></h2>
          </li>
        </ul>
      </section>
      <nav>
        <a href="https://forum.example.com/page/2">Next page</a>
      </nav>
    </main>
  </body>
</html>
"""
case_four_results = run_topic_links_snapshot(case_four_html, script_dir)
case_four_hrefs = [item.get("href") for item in case_four_results]
assert "https://forum.example.com/t/nested-one" in case_four_hrefs, case_four_results
assert "https://forum.example.com/t/nested-two" in case_four_hrefs, case_four_results
assert "https://forum.example.com/page/2" not in case_four_hrefs, case_four_results

# Case 5: modifier class variance should still count as repeated result containers.
case_five_html = """
<!doctype html>
<html>
  <body>
    <main>
      <ul>
        <li class="result featured">
          <a href="https://forum.example.com/u/featured-author">featured-author</a>
          <h2><a class="topic title" href="https://forum.example.com/t/featured-topic">Featured topic</a></h2>
        </li>
        <li class="result">
          <a href="https://forum.example.com/u/normal-author">normal-author</a>
          <h2><a class="topic title" href="https://forum.example.com/t/normal-topic">Normal topic</a></h2>
        </li>
      </ul>
      <nav><a href="https://forum.example.com/page/3">Page 3</a></nav>
    </main>
  </body>
</html>
"""
case_five_results = run_topic_links_snapshot(case_five_html, script_dir)
case_five_hrefs = [item.get("href") for item in case_five_results]
assert "https://forum.example.com/t/featured-topic" in case_five_hrefs, case_five_results
assert "https://forum.example.com/t/normal-topic" in case_five_hrefs, case_five_results
assert "https://forum.example.com/u/featured-author" not in case_five_hrefs, case_five_results
assert "https://forum.example.com/u/normal-author" not in case_five_hrefs, case_five_results
assert "https://forum.example.com/page/3" not in case_five_hrefs, case_five_results
PY
