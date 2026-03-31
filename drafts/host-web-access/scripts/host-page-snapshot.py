#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = Path(__file__).resolve().parents[5]
CDP_SNAPSHOT = ROOT_DIR / "ubuntu-browser-session" / "scripts" / "cdp-snapshot.py"


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture page snapshot via CDP")
    parser.add_argument("--port", type=int, default=9222)
    parser.add_argument("--target-id")
    parser.add_argument("--format", choices=["markdown", "text", "links", "topic-links"], default="markdown")
    parser.add_argument("--max-chars", type=int)
    args = parser.parse_args()

    cmd = [sys.executable, str(CDP_SNAPSHOT), "--port", str(args.port), "--format", args.format]
    if args.target_id:
        cmd += ["--target-id", args.target_id]
    if args.max_chars is not None:
        cmd += ["--max-chars", str(args.max_chars)]
    subprocess.run(cmd, check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
