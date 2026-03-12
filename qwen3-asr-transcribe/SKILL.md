---
name: qwen3-asr-transcribe
description: Transcribe local audio or video files, or directly accessible media URLs, into text with a bundled Qwen3 ASR runtime. Use when asked to convert speech to text, produce subtitles, extract notes from meetings or interviews, or process long recordings with a portable skill that can be moved across Agent environments.
---

# Qwen3 Asr Transcribe

Use `{baseDir}/.venv/bin/python {baseDir}/scripts/transcribe_audio.py` instead of reimplementing transcription logic. The script ships with its own runtime under `scripts/qwen3_asr_runtime/`, auto-loads API keys from local `.asr_env` or `.env` files, and handles long recordings by splitting them with Silero VAD.

This skill expects a local runtime:

- `{baseDir}/.venv` is a local virtual environment and is not committed
- `{baseDir}/.asr_env` or `.env` may be used for local credentials and is not committed

## Workflow

1. Confirm that the source is a local media file or an accessible `http`/`https` URL.
2. If `{baseDir}/.venv/bin/python` is missing, create the local venv and install the required Python packages first.
3. Run `{baseDir}/.venv/bin/python {baseDir}/scripts/transcribe_audio.py` with the input path and any needed options.
4. Read the generated `.txt`, `.srt`, or `.json` outputs, or use `--stdout` when the caller needs the transcript directly in terminal output.
5. Open `references/runtime-notes.md` only when environment setup, dependency issues, or credential loading behavior need clarification.

## Quick Start

Run from the skill directory or by passing the script path directly:

```bash
{baseDir}/.venv/bin/python {baseDir}/scripts/transcribe_audio.py \
  -i "/path/to/audio-or-video.mp3" \
  --stdout
```

Generate subtitles and JSON metadata:

```bash
{baseDir}/.venv/bin/python {baseDir}/scripts/transcribe_audio.py \
  -i "meeting.mp4" \
  --srt \
  --json \
  --context "人名、术语、项目代号"
```

## Options

- `-i, --input`: Required. Local audio/video path or `http`/`https` media URL.
- `-o, --output-dir`: Optional. Directory for generated outputs. Default: next to the local file, or the current working directory for URLs.
- `--context`: Optional domain hints for names, jargon, or acronyms.
- `-j, --num-threads`: Parallel ASR calls for split segments. Default `4`.
- `-d, --vad-segment-threshold`: Preferred split size in seconds before forced re-chunking. Default `120`.
- `--srt`: Write subtitle output.
- `--json`: Write a JSON summary with language, transcript, and segment timings.
- `--stdout`: Print only the final transcript to stdout after writing files.
- `--tmp-dir`: Optional directory for temporary split audio files.
- `--keep-temp`: Keep temporary split files for debugging.
- `--dashscope-api-key`: Override `.asr_env`, `.env`, or environment variables.

## Output Contract

- Always write a UTF-8 `.txt` transcript file.
- Prefix the `.txt` file with the detected language on the first line, then the full transcript.
- Write `.srt` only when `--srt` is supplied.
- Write `.json` only when `--json` is supplied.
- Prefer `--stdout` when another agent step needs the transcript immediately.

## Guardrails

- Do not ask the user to paste the API key if a nearby `.asr_env` or `.env` file is present.
- Prefer the bundled script over project-local entrypoints because the skill runtime is self-contained, Windows-safe, and portable across Agent environments.
- If `{baseDir}/.venv/bin/python` is missing, create the local venv first and install the required Python packages there before invoking the skill.
- If decoding fails on compressed media, verify that `ffmpeg` is installed and available on `PATH`.
