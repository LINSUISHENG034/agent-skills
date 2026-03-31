# Node Whisper Runtime Contract

## Purpose

`node-whisper` is a draft skill for running Whisper transcription on a remote Windows GPU node instead of the local Linux or OpenClaw gateway host.

Its current job is to make the remote runtime reproducible:

1. reach the Windows GPU host
2. install and validate a dedicated Whisper runtime
3. define stable path and execution assumptions
4. preserve a clean path to a future OpenClaw node-host execution path

In one sentence:

> Offload open-source Whisper transcription from a GPU-poor gateway host to a GPU-capable Windows node.

## Problem Shape

The gateway host does not have a suitable GPU for larger Whisper models or long recordings. A Windows machine with an NVIDIA GPU is available, but the workflow needs an explicit runtime contract instead of ad hoc one-off commands.

The draft must answer:

1. how the agent reaches the Windows GPU host
2. how the remote runtime is installed and repaired
3. how audio paths become visible on the Windows side
4. how failures are surfaced through a user-facing wrapper

## Goals

- Reuse the existing OpenClaw node model instead of inventing a parallel RPC service
- Support Windows + NVIDIA GPU as the first real execution target
- Keep the first version script-driven and easy to repair
- Make bootstrap and diagnostics reproducible from Linux
- Preserve a future path to OpenClaw node-host execution if needed

## Non-Goals

The draft does not try to:

- build a persistent HTTP transcription service
- auto-sync arbitrary audio files between Linux and Windows
- load-balance across multiple remote nodes
- auto-select models based on file size or difficulty
- hide every Windows environment difference behind opaque automation
- treat transcript parity as the first release gate

## Intended User

- A user whose gateway host lacks a suitable GPU
- A user who already has a reachable Windows GPU machine
- A user who wants an open-source local ASR path before optimizing quality

## Core Execution Contract

### Runtime root

- Windows root: `E:\Projects`
- Linux mapped root: `/mnt/win/Projects`
- Runtime directory: `E:\Projects\node-whisper-runtime`
- Linux mapped view: `/mnt/win/Projects/node-whisper-runtime`

Keep this path stable. It is the anchor for:

- the managed venv
- copied fixtures
- generated transcripts and JSON
- helper scripts uploaded to the Windows host

### Runtime stack

- environment manager: `uv`
- preferred Python: `3.12`
- ASR engine: `faster-whisper`
- first smoke model: `tiny`
- real validation model: `large-v3`
- preferred device: `cuda`
- preferred compute type: `float16`

### Transport model

- maintenance path: SSH
- current packaged script path: SSH-backed orchestration from Linux
- target long-term execution path: OpenClaw `node host` backed execution

As of March 31, 2026, the OpenClaw CLI and docs distinguish:

- `openclaw nodes run` as a mac-focused shell command path
- `openclaw nodes invoke` as capability invocation, with `system.run` blocked there

This draft therefore keeps SSH as the concrete Windows transport while shaping
the wrapper around a future node-host-backed execution contract.

### File visibility

Audio must either:

- already exist on the Windows node, or
- be copied there explicitly by the wrapper or validation script

Do not assume transparent Linux-to-Windows file visibility.

## Capability Boundary

The draft should support:

- selecting or defaulting the target node
- validating the remote environment
- installing the Windows runtime when missing
- repairing the Windows runtime when the smoke gate fails
- running controlled transcription commands
- returning text or JSON outputs
- reporting missing node, path, or runtime prerequisites clearly

## Release Gate For This Draft

Treat the draft as operational when:

1. the remote Windows GPU runtime can be bootstrapped from Linux
2. the smoke test proves CUDA-backed inference works
3. a real fixture can be transcribed end-to-end
4. artifacts are written into the runtime path and copied back for inspection

Quality tuning is intentionally deferred until the runtime contract is stable.
