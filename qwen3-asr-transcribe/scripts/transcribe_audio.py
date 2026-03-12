#!/usr/bin/env python3
"""Standalone skill wrapper around a bundled Qwen3 ASR runtime."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import shutil
import tempfile
from collections import Counter
from datetime import timedelta
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse

import dashscope
import requests
import srt
from silero_vad import load_silero_vad

from qwen3_asr_runtime.audio_tools import WAV_SAMPLE_RATE, load_audio, process_vad, save_audio_file
from qwen3_asr_runtime.qwen3asr import QwenASR


SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_ROOT = SCRIPT_DIR.parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Transcribe media with the bundled portable Qwen3 ASR skill runtime."
    )
    parser.add_argument("-i", "--input", required=True, help="Local media path or http/https URL.")
    parser.add_argument("-o", "--output-dir", help="Directory for generated transcript files.")
    parser.add_argument("--context", default="", help="Optional ASR context text.")
    parser.add_argument(
        "--dashscope-api-key",
        help="Optional DashScope API key. Overrides environment variables and local .asr_env files.",
    )
    parser.add_argument(
        "-j",
        "--num-threads",
        type=int,
        default=4,
        help="Parallel ASR calls for segmented audio.",
    )
    parser.add_argument(
        "-d",
        "--vad-segment-threshold",
        type=int,
        default=120,
        help="Preferred VAD segment size in seconds for long media.",
    )
    parser.add_argument("--tmp-dir", help="Directory for temporary split audio.")
    parser.add_argument("--srt", action="store_true", help="Write SRT subtitles.")
    parser.add_argument("--json", action="store_true", help="Write JSON metadata.")
    parser.add_argument("--stdout", action="store_true", help="Print transcript to stdout.")
    parser.add_argument(
        "--keep-temp",
        action="store_true",
        help="Keep temporary split audio for debugging.",
    )
    return parser.parse_args()


def read_simple_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("'").strip('"')
    return values


def iter_env_files() -> list[Path]:
    candidates = [
        Path.cwd() / ".asr_env",
        Path.cwd() / ".env",
        SKILL_ROOT / ".asr_env",
        SKILL_ROOT / ".env",
    ]
    deduped = []
    seen = set()
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved not in seen:
            deduped.append(resolved)
            seen.add(resolved)
    return deduped


def resolve_api_key(cli_value: str | None) -> str:
    if cli_value:
        return cli_value.strip()

    for env_name in ("DASHSCOPE_API_KEY", "DASHSCOPE_API"):
        value = os.environ.get(env_name)
        if value:
            return value.strip()

    for env_path in iter_env_files():
        env_values = read_simple_env(env_path)
        for env_name in ("DASHSCOPE_API_KEY", "DASHSCOPE_API"):
            value = env_values.get(env_name)
            if value:
                return str(value).strip()

    raise RuntimeError(
        "DashScope API key not found. Set DASHSCOPE_API_KEY, DASHSCOPE_API, or provide .asr_env/.env near the skill or current working directory."
    )


def ensure_input_exists(input_value: str) -> None:
    if input_value.startswith(("http://", "https://")):
        response = requests.head(input_value, allow_redirects=True, timeout=10)
        if response.status_code >= 400:
            raise FileNotFoundError(
                f"Remote input '{input_value}' is inaccessible. Status code: {response.status_code}."
            )
        return

    if not Path(input_value).exists():
        raise FileNotFoundError(f"Input file does not exist: {input_value}")


def slugify_source(input_value: str) -> str:
    if input_value.startswith(("http://", "https://")):
        parsed = urlparse(input_value)
        stem = Path(parsed.path).stem
        if stem:
            return stem
        digest = hashlib.sha1(input_value.encode("utf-8")).hexdigest()[:12]
        return f"remote-{digest}"
    return Path(input_value).stem


def resolve_output_base(input_value: str, output_dir: str | None) -> Path:
    source_name = slugify_source(input_value)
    if output_dir:
        directory = Path(output_dir)
    elif input_value.startswith(("http://", "https://")):
        directory = Path.cwd()
    else:
        directory = Path(input_value).resolve().parent
    directory.mkdir(parents=True, exist_ok=True)
    return directory / source_name


def build_segments(wav, threshold_seconds: int):
    if len(wav) / WAV_SAMPLE_RATE < 180:
        return [(0, len(wav), wav)]

    vad_model = load_silero_vad(onnx=True)
    return process_vad(wav, vad_model, segment_threshold_s=threshold_seconds)


def write_text_output(path: Path, language: str, transcript: str) -> None:
    path.write_text(f"{language}\n{transcript}\n", encoding="utf-8")


def write_srt_output(path: Path, ordered_results: list[tuple[int, str]], segments) -> None:
    subtitles = []
    for idx, (_, text) in enumerate(ordered_results, start=1):
        start_sample, end_sample, _ = segments[idx - 1]
        subtitles.append(
            srt.Subtitle(
                index=idx,
                start=timedelta(seconds=start_sample / WAV_SAMPLE_RATE),
                end=timedelta(seconds=end_sample / WAV_SAMPLE_RATE),
                content=text,
            )
        )
    path.write_text(srt.compose(subtitles), encoding="utf-8")


def write_json_output(
    path: Path,
    input_value: str,
    language: str,
    transcript: str,
    ordered_results: list[tuple[int, str]],
    segments,
) -> None:
    payload = {
        "source": input_value,
        "language": language,
        "transcript": transcript,
        "segments": [
            {
                "index": idx,
                "start_seconds": segments[idx][0] / WAV_SAMPLE_RATE,
                "end_seconds": segments[idx][1] / WAV_SAMPLE_RATE,
                "text": text,
            }
            for idx, (_, text) in enumerate(ordered_results)
        ],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def iter_segment_paths(segment_dir: Path, segments: Iterable[tuple[int, int, object]]) -> list[Path]:
    paths = []
    for index, (_, _, wav_data) in enumerate(segments):
        segment_path = segment_dir / f"segment_{index:04d}.wav"
        save_audio_file(wav_data, str(segment_path))
        paths.append(segment_path)
    return paths


def transcribe_segments(
    qwen_asr: QwenASR, segment_paths: list[Path], context: str, num_threads: int
) -> tuple[str, list[tuple[int, str]]]:
    results: list[tuple[int, str]] = []
    languages: list[str] = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = {
            executor.submit(qwen_asr.asr, str(segment_path), context): index
            for index, segment_path in enumerate(segment_paths)
        }
        for future in concurrent.futures.as_completed(futures):
            index = futures[future]
            language, text = future.result()
            results.append((index, text))
            languages.append(language)

    results.sort(key=lambda item: item[0])
    language = Counter(languages).most_common(1)[0][0] if languages else "Unknown"
    return language, results


def main() -> int:
    args = parse_args()
    ensure_input_exists(args.input)

    api_key = resolve_api_key(args.dashscope_api_key)
    dashscope.api_key = api_key
    os.environ["DASHSCOPE_API_KEY"] = api_key

    output_base = resolve_output_base(args.input, args.output_dir)
    temp_root = Path(args.tmp_dir).resolve() if args.tmp_dir else None
    if temp_root:
        temp_root.mkdir(parents=True, exist_ok=True)
        temp_dir = Path(tempfile.mkdtemp(dir=temp_root, prefix="qwen3-asr-skill-"))
    else:
        temp_dir = Path(tempfile.mkdtemp(prefix="qwen3-asr-skill-"))

    try:
        wav = load_audio(args.input)
        segments = build_segments(wav, args.vad_segment_threshold)
        segment_paths = iter_segment_paths(temp_dir, segments)

        qwen_asr = QwenASR(model="qwen3-asr-flash")
        language, ordered_results = transcribe_segments(
            qwen_asr, segment_paths, args.context, args.num_threads
        )
        transcript = " ".join(text for _, text in ordered_results).strip()

        txt_path = output_base.with_suffix(".txt")
        write_text_output(txt_path, language, transcript)

        if args.srt:
            write_srt_output(output_base.with_suffix(".srt"), ordered_results, segments)

        if args.json:
            write_json_output(
                output_base.with_suffix(".json"),
                args.input,
                language,
                transcript,
                ordered_results,
                segments,
            )

        if args.stdout:
            print(transcript)
        else:
            print(f"Language: {language}")
            print(f"Transcript file: {txt_path}")
            if args.srt:
                print(f"SRT file: {output_base.with_suffix('.srt')}")
            if args.json:
                print(f"JSON file: {output_base.with_suffix('.json')}")

        return 0
    finally:
        if args.keep_temp:
            print(f"Temporary files kept at: {temp_dir}", file=sys.stderr)
        else:
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
