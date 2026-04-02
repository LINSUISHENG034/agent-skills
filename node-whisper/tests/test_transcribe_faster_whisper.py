#!/usr/bin/env python3
import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRANSCRIBE_SCRIPT = ROOT / "scripts" / "transcribe_faster_whisper.py"


class TranscribeFasterWhisperTests(unittest.TestCase):
    def test_success_payload_includes_timing_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            audio = root / "sample.wav"
            text_out = root / "transcript.txt"
            json_out = root / "transcript.json"
            module_dir = root / "stub_modules"
            module_dir.mkdir()
            audio.write_bytes(b"RIFF0000WAVEfmt ")

            (module_dir / "faster_whisper.py").write_text(
                textwrap.dedent(
                    """
                    class Segment:
                        def __init__(self, start, end, text):
                            self.start = start
                            self.end = end
                            self.text = text
                            self.avg_logprob = -0.1
                            self.no_speech_prob = 0.01


                    class Info:
                        language = "en"
                        language_probability = 0.99
                        duration = 3.2
                        duration_after_vad = 3.0


                    class WhisperModel:
                        def __init__(self, model, device="cuda", compute_type="float16"):
                            self.model = model
                            self.device = device
                            self.compute_type = compute_type

                        def transcribe(self, audio_path, beam_size=5, language=None):
                            return iter([
                                Segment(0.0, 1.0, "hello "),
                                Segment(1.0, 2.0, "world"),
                            ]), Info()
                    """
                ),
                encoding="utf-8",
            )

            env = os.environ.copy()
            env["PYTHONPATH"] = f"{module_dir}:{env.get('PYTHONPATH', '')}"

            result = subprocess.run(
                [
                    str(TRANSCRIBE_SCRIPT),
                    "--audio",
                    str(audio),
                    "--text-out",
                    str(text_out),
                    "--json-out",
                    str(json_out),
                ],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout.strip())
            saved = json.loads(json_out.read_text(encoding="utf-8"))
            self.assertTrue(text_out.exists())
            self.assertEqual(text_out.read_text(encoding="utf-8"), "hello world")
            for data in (payload, saved):
                self.assertTrue(data["ok"])
                self.assertEqual(data["stage"], "done")
                self.assertIn("model_load_seconds", data)
                self.assertIn("transcribe_seconds", data)
                self.assertIn("total_seconds", data)
                self.assertIsInstance(data["model_load_seconds"], float)
                self.assertIsInstance(data["transcribe_seconds"], float)
                self.assertIsInstance(data["total_seconds"], float)
                self.assertGreaterEqual(data["model_load_seconds"], 0.0)
                self.assertGreaterEqual(data["transcribe_seconds"], 0.0)
                self.assertGreaterEqual(data["total_seconds"], 0.0)


if __name__ == "__main__":
    unittest.main()
