#!/usr/bin/env python3
import argparse
import json
import sys
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True)
    parser.add_argument("--model", default="large-v3")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--compute-type", default="float16")
    parser.add_argument("--beam-size", type=int, default=5)
    parser.add_argument("--language", default=None)
    parser.add_argument("--text-out", required=True)
    parser.add_argument("--json-out", required=False)
    parser.add_argument("--timestamps", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    started_at = time.perf_counter()

    try:
        from faster_whisper import WhisperModel
    except Exception as exc:
        print(json.dumps({"ok": False, "stage": "import", "error": str(exc)}))
        return 1

    audio_path = Path(args.audio)
    if not audio_path.exists():
        print(json.dumps({"ok": False, "stage": "input", "error": f"audio not found: {audio_path}"}))
        return 1

    model_load_started_at = time.perf_counter()
    try:
        model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)
    except Exception as exc:
        print(json.dumps({"ok": False, "stage": "model_load", "error": str(exc)}))
        return 1
    model_load_seconds = time.perf_counter() - model_load_started_at

    transcribe_started_at = time.perf_counter()
    try:
        segments_iter, info = model.transcribe(
            str(audio_path),
            beam_size=args.beam_size,
            language=args.language,
        )
        segments = list(segments_iter)
    except Exception as exc:
        print(json.dumps({"ok": False, "stage": "transcribe", "error": str(exc)}))
        return 1
    transcribe_seconds = time.perf_counter() - transcribe_started_at

    text = "".join(segment.text for segment in segments).strip()
    text_out = Path(args.text_out)
    json_out = Path(args.json_out) if args.json_out else None
    text_out.parent.mkdir(parents=True, exist_ok=True)
    if json_out:
        json_out.parent.mkdir(parents=True, exist_ok=True)
    text_out.write_text(text, encoding="utf-8")

    payload = {
        "ok": True,
        "stage": "done",
        "audio": str(audio_path),
        "model": args.model,
        "device": args.device,
        "compute_type": args.compute_type,
        "beam_size": args.beam_size,
        "language": getattr(info, "language", None),
        "language_probability": getattr(info, "language_probability", None),
        "duration": getattr(info, "duration", None),
        "duration_after_vad": getattr(info, "duration_after_vad", None),
        "segment_count": len(segments),
        "model_load_seconds": model_load_seconds,
        "transcribe_seconds": transcribe_seconds,
        "total_seconds": time.perf_counter() - started_at,
        "text_out": str(text_out),
    }
    if json_out:
        payload["json_out"] = str(json_out)
    if args.timestamps:
        payload["segments"] = [
            {
                "start": segment.start,
                "end": segment.end,
                "text": segment.text,
                "avg_logprob": segment.avg_logprob,
                "no_speech_prob": segment.no_speech_prob,
            }
            for segment in segments
        ]
    if json_out:
        json_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
