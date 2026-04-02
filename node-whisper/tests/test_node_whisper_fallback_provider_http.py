#!/usr/bin/env python3
import json
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / "scripts" / "node_whisper_fallback_provider_http.py"


class _Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        content_length = int(self.headers.get("Content-Length", "0"))
        self.server.last_body = self.rfile.read(content_length)  # type: ignore[attr-defined]
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(
            json.dumps(
                {
                    "text": "fallback provider transcript",
                    "language": "en",
                    "duration": 12.5,
                }
            ).encode("utf-8")
        )

    def log_message(self, format, *args):  # noqa: A003
        return


class NodeWhisperFallbackHttpProviderTests(unittest.TestCase):
    def test_http_generic_provider_writes_outputs_and_returns_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            media = root / "sample.wav"
            config = root / "fallback.json"
            output_dir = root / "out"
            media.write_bytes(b"RIFF0000WAVEfmt ")

            server = HTTPServer(("127.0.0.1", 0), _Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                config.write_text(
                    json.dumps({"url": f"http://127.0.0.1:{server.server_port}/transcribe"}),
                    encoding="utf-8",
                )
                result = subprocess.run(
                    [
                        str(PROVIDER),
                        "--provider",
                        "http-generic",
                        "--input",
                        str(media),
                        "--input-stem",
                        "sample",
                        "--output-dir",
                        str(output_dir),
                        "--config",
                        str(config),
                        "--want-json",
                    ],
                    cwd=ROOT,
                    text=True,
                    capture_output=True,
                )
            finally:
                server.shutdown()
                thread.join(timeout=5)
                server.server_close()

            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout.strip())
            text_out = Path(payload["local_text_out"])
            json_out = Path(payload["local_json_out"])

            self.assertEqual(payload["engine"], "fallback")
            self.assertEqual(payload["provider"], "http-generic")
            self.assertEqual(payload["language"], "en")
            self.assertEqual(payload["duration"], 12.5)
            self.assertTrue(text_out.exists())
            self.assertTrue(json_out.exists())
            self.assertEqual(text_out.read_text(encoding="utf-8"), "fallback provider transcript")
            saved = json.loads(json_out.read_text(encoding="utf-8"))
            self.assertEqual(saved["provider"], "http-generic")
            self.assertEqual(saved["text_out"], str(text_out))
            self.assertEqual(saved["provider_response"]["text"], "fallback provider transcript")


if __name__ == "__main__":
    unittest.main()
