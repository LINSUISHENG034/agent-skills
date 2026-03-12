# Runtime Notes

## Credential Inputs

- The script checks, in order: CLI key, environment variables, current working directory `.asr_env` or `.env`, then skill-root `.asr_env` or `.env`.
- The bundled script accepts both `DASHSCOPE_API_KEY` and `DASHSCOPE_API`.
- `.asr_env`, `.env`, and `.venv` are local runtime files and are intentionally not committed to the repository.

## Bundled Runtime Modules

- `scripts/qwen3_asr_runtime/audio_tools.py`
- `scripts/qwen3_asr_runtime/qwen3asr.py`

These are copied into the skill so the skill can move independently of any specific repository.

## Common Failure Modes

- Missing `ffmpeg`: compressed audio or video cannot be decoded.
- Missing Python dependencies: install `dashscope`, `librosa`, `pydub`, `silero_vad`, `soundfile`, `requests`, and `srt`.
- Invalid DashScope key: API requests fail before transcription completes.
- Inaccessible URL: remote media path returns a non-2xx/3xx status.

## Temporary Files

- Split audio is written to a temporary folder under the provided `--tmp-dir`, or the system temp directory by default.
- Converted `.mp3` chunks created by `QwenASR.asr()` stay inside that temporary folder and are removed with the folder unless `--keep-temp` is used.
