---
name: node-whisper
description: >-
  Use when a local audio or video file must be transcribed on a paired LAN
  Windows NVIDIA GPU node instead of the current Linux or OpenClaw gateway
  host, or when that remote runtime needs probing, repair, or validation.
metadata:
  version: 0.1.0
---

# Node Whisper

Transcribe one local audio or video file through a LAN Windows GPU node when
the current host is not the right machine for inference.

The public entrypoint is:

```bash
{baseDir}/scripts/node_whisper_orchestrate.sh /path/to/media.wav
```

Add flags as needed:

```bash
{baseDir}/scripts/node_whisper_orchestrate.sh /path/to/media.mp4 \
  --json \
  --timestamps \
  --language zh \
  --model large-v3
```

The wrapper owns:

1. input validation
2. remote readiness checks
3. runtime repair or install when needed
4. explicit media staging to Windows
5. remote transcription execution
6. transcript fetch back to the local host

Transcript text stays on stdout. Operational noise and summaries stay on stderr.
Default runs also emit coarse phase markers on stderr for `validate`, `ready`,
`stage`, `transcribe`, and `fetch`. `--quiet` suppresses those progress
markers and keeps stderr reserved for errors only.

## Local Config

The shell entrypoints auto-load `{baseDir}/.env` from the skill root for
machine-specific settings such as the Windows SSH user, host, key path, and
runtime root.

Keep the local-only file in:

- `{baseDir}/.env`

Use the publishable template as the starting point:

- `{baseDir}/.env.example`

For SSH bootstrap, keep the public key in the local-only `.env` as
`NODE_WHISPER_SSH_PUBLIC_KEY` rather than hardcoding it in publishable scripts.

## Do Not Use

- Paid API selection or API-key-based transcription workflows
- Pure ASR quality tuning, prompt tuning, or decoding research
- Cases where the Windows node is unavailable and no remote GPU path exists
- Cases where the local file cannot be copied to the Windows side
- URL input, directory batches, or multi-node routing in the current draft

## Supported Inputs And Outputs

Supported input:

- one local audio file path
- one local video file path

Default output:

- transcript text on stdout

Optional output:

- JSON artifact with metadata when `--json` is requested
- timestamped segments when `--timestamps` is requested

Familiar public flags intentionally stay close to `local-whisper` where that
fits the remote-node model:

- `--model`
- `--language`
- `--json`
- `--timestamps`
- `--quiet`

## Runtime Contract

- Windows runtime root: `E:\Projects\node-whisper-runtime`
- Linux mapped root: `/mnt/win/Projects/node-whisper-runtime`
- Preferred environment manager: `uv`
- Preferred engine: `faster-whisper`
- Current scriptable transport: SSH for bootstrap, repair, staging, and run
- Target long-term execution direction: OpenClaw `node host` backed execution

The audio source must already be reachable on Windows or be copied there as part
of the workflow. Do not assume hidden sync.

Machine-specific values should come from the skill-root `.env`, not from
published hardcoded defaults.

## Workflow

1. Validate one local media input path.
2. Probe the remote Windows node for `uv`, Python, `ffmpeg`, and `nvidia-smi`.
3. Run install or repair automatically if the runtime is not yet healthy.
4. Re-run the smoke test as the confidence gate after repair.
5. Create a remote job directory and copy the local media there.
6. Run `faster-whisper` on the Windows GPU node.
7. Fetch transcript text and optional JSON back to the local host.

## Entry Scripts

- Main packaged entrypoint: `{baseDir}/scripts/node_whisper_orchestrate.sh`
- Input normalization: `{baseDir}/scripts/node_whisper_validate_input.sh`
- Readiness and repair gate: `{baseDir}/scripts/node_whisper_require_ready.sh`
- Media staging: `{baseDir}/scripts/node_whisper_stage_media.sh`
- Result fetch: `{baseDir}/scripts/node_whisper_fetch_results.sh`
- SSH bootstrap on Windows: `{baseDir}/scripts/install-node-whisper-ssh-key.ps1`
- Environment probe from Linux: `{baseDir}/scripts/run-node-whisper-env-probe.sh`
- Runtime install from Linux: `{baseDir}/scripts/run-node-whisper-install.sh`
- Runtime smoke test from Linux: `{baseDir}/scripts/run-node-whisper-smoke.sh`

## Guardrails

- Keep the Windows runtime root stable. Do not silently move it to a user-profile path.
- Prefer explicit path mapping over hidden file transfer logic.
- Keep transcript text clean on stdout; keep operational chatter off stdout.
- Treat current SSH automation and future node-host execution as separate layers.
- Record validation artifacts before claiming the runtime is operational.
- Treat runtime viability as the current release gate; do not claim transcript parity.
- Keep this draft portable. Host-specific results belong in reusable summaries
  plus stored artifacts, not in the main workflow.

## Success Bar

Treat the draft as usable only when all of the following are true:

1. SSH or node-level reachability is confirmed.
2. `uv`, `nvidia-smi`, and a usable Python interpreter are present.
3. The managed runtime installs under the fixed root.
4. The smoke test returns `ok: true` on CUDA.
5. A real media transcription completes end-to-end through the packaged entrypoint.

## References

- Runtime goals, scope, and execution contract: [references/runtime-contract.md](references/runtime-contract.md)
- Packaged entrypoint behavior and limitations: [references/packaged-workflow.md](references/packaged-workflow.md)
- SSH, probe, install, and smoke bootstrap details: [references/bootstrap.md](references/bootstrap.md)
- Probe, smoke, and large-v3 validation evidence: [references/validation.md](references/validation.md)
