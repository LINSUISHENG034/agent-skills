# Node Whisper Packaged Workflow

## Public Entry Point

Use the packaged wrapper first:

```bash
{baseDir}/scripts/node_whisper_orchestrate.sh /path/to/media.wav
```

Common options:

```bash
{baseDir}/scripts/node_whisper_orchestrate.sh /path/to/media.mp4 \
  --json \
  --timestamps \
  --language zh \
  --model large-v3
```

Explicit fallback remains opt-in:

```bash
{baseDir}/scripts/node_whisper_orchestrate.sh /path/to/media.mp4 \
  --fallback-provider http-generic
```

Before normal use, copy `{baseDir}/.env.example` to `{baseDir}/.env` and fill in
the machine-specific values for your Windows host. The shell scripts auto-load
the skill-root `.env`.

## Input Contract

Supported in the current draft:

- one local audio file path
- one local video file path

Not supported in the current draft:

- URLs
- directory batches
- multi-node scheduling

## Output Contract

Default:

- transcript text on stdout

Optional:

- JSON artifact when `--json` is requested
- timestamped segments when `--timestamps` is requested

Operational logs and summaries should stay off stdout so other steps can consume
the transcript directly.

## What The Wrapper Owns

For one request, the wrapper is responsible for:

1. validating the local media path
2. checking the remote Windows runtime
3. repairing or installing the runtime if needed
4. creating a remote job directory
5. copying the media file to the Windows node
6. executing `faster-whisper` remotely
7. fetching transcript text and optional JSON back locally

## Current Transport Reality

As of March 31, 2026:

- the local OpenClaw CLI documents `openclaw nodes run` as a mac-focused shell command path
- the official docs document `nodes invoke` as a capability layer where `system.run` is blocked

Because of that, this draft keeps SSH as the concrete automation transport for
Windows while preserving a node-host-oriented contract for later integration.

## Public Flags

Keep the public CLI close to `local-whisper` where it helps usability:

- `--model`
- `--language`
- `--json`
- `--timestamps`
- `--quiet`
- `--fallback-provider`
- `--fallback-config`

Added for remote packaging:

- `--node`
- `--force-repair`
- `--transport`
- `--output-dir`
- `--dry-run`

## Local Config Files

Local-only:

- `{baseDir}/.env`

Publishable template:

- `{baseDir}/.env.example`

The intended variables are:

- `NODE_WHISPER_REMOTE_USER`
- `NODE_WHISPER_REMOTE_HOST`
- `NODE_WHISPER_SSH_KEY`
- `NODE_WHISPER_SSH_PUBLIC_KEY`
- `NODE_WHISPER_RUNTIME_DIR`
- `NODE_WHISPER_TRANSPORT`
- `NODE_WHISPER_NODE_NAME`
- `NODE_WHISPER_FALLBACK_HTTP_URL`
- `NODE_WHISPER_FALLBACK_HTTP_HEADERS_JSON`
- `NODE_WHISPER_FALLBACK_HTTP_EXTRA_FORM_JSON`
- `NODE_WHISPER_FALLBACK_HTTP_FILE_FIELD`
- `NODE_WHISPER_FALLBACK_HTTP_TEXT_FIELD`
- `NODE_WHISPER_FALLBACK_HTTP_LANGUAGE_FIELD`

## Dry Run

Use dry-run when you want to inspect normalized input handling without touching
the remote host:

```bash
{baseDir}/scripts/node_whisper_orchestrate.sh /path/to/media.wav --dry-run
```

## Failure Classes

The wrapper should normalize failures into stable user-facing classes:

- `input_not_found`
- `unsupported_input_type`
- `node_unreachable`
- `node_runtime_repair_failed`
- `input_stage_failed`
- `transcription_failed`
- `result_fetch_failed`
- `unsupported_fallback_provider`
- `fallback_missing_configuration`
- `fallback_provider_unreachable`
- `fallback_provider_http_error`
- `fallback_invalid_response`

## Explicit Fallback

Fallback is never automatic. The wrapper only attempts a fallback provider when
the caller passes `--fallback-provider <name>`.

Current provider:

- `http-generic`

Current trigger scope:

- fallback is attempted only for eligible ready-gate failures
- fallback is not a blanket retry path for every remote execution failure

See `references/fallback-contract.md` for the provider contract and configuration surface.
