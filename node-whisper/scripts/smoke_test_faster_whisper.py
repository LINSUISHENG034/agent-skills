#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    try:
        from faster_whisper import WhisperModel
    except Exception as exc:
        print(json.dumps({"ok": False, "stage": "import", "error": str(exc)}))
        return 1

    with tempfile.TemporaryDirectory(prefix="node-whisper-") as tmpdir:
        wav_path = Path(tmpdir) / "silence.wav"
        ffmpeg_cmd = [
            "ffmpeg",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "anullsrc=r=16000:cl=mono",
            "-t",
            "1",
            str(wav_path),
        ]
        ffmpeg = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
        if ffmpeg.returncode != 0:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "stage": "ffmpeg",
                        "error": ffmpeg.stderr.strip() or "ffmpeg failed",
                    }
                )
            )
            return 1

        try:
            model = WhisperModel("tiny", device="cuda", compute_type="float16")
        except Exception as exc:
            print(json.dumps({"ok": False, "stage": "model_load", "error": str(exc)}))
            return 1

        try:
            segments, info = model.transcribe(str(wav_path), beam_size=1)
            segments_list = list(segments)
        except Exception as exc:
            print(json.dumps({"ok": False, "stage": "transcribe", "error": str(exc)}))
            return 1

        payload = {
            "ok": True,
            "stage": "done",
            "model": "tiny",
            "device": "cuda",
            "compute_type": "float16",
            "language": getattr(info, "language", None),
            "language_probability": getattr(info, "language_probability", None),
            "segment_count": len(segments_list),
            "text": " ".join(segment.text.strip() for segment in segments_list if segment.text).strip(),
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0


if __name__ == "__main__":
    sys.exit(main())
