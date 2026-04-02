# Node Whisper Validation

## Current Status

The draft has already proven runtime viability on a real Windows GPU host. These results support the runtime contract; they do not claim transcript parity with a paid reference system.

The packaged entrypoint builds on these stored validation results. It does not
replace them as evidence that the Windows GPU path is real.

## Validation Summary

Local validation to date has established:

- the Windows host exposed a usable SSH path
- `uv`, Python, `ffmpeg`, and `nvidia-smi` were available
- the managed `faster-whisper` runtime installed successfully
- the CUDA smoke test returned `ok: true`
- a long-form real media transcription completed end to end with `large-v3`

These observations are sufficient for the current release gate, which is runtime
viability rather than transcript parity.

## Practical Conclusion

The remote Windows GPU path is already operational enough for runtime-oriented work. Revisit language forcing, segmentation, VAD, and decoding parameters only after the execution contract is wrapped cleanly for normal use.

## Model Load Timing Observation

On 2026-04-02, repeated-run timing was measured against the same 90-second real
video clip derived locally from:

- `/mnt/sda3/Movies/书记 (2009)/书记 (2009) 480p AAC.mp4`

Measurement shape:

- local clip length: about 90 seconds
- model: `large-v3`
- device: `cuda`
- two sequential runs against the same Windows runtime and the same media clip

Observed timings:

| Run | model_load_seconds | transcribe_seconds | total_seconds | wall_seconds |
|-----|--------------------|--------------------|---------------|--------------|
| 1 | 4.60 | 14.14 | 19.11 | 21.93 |
| 2 | 4.58 | 14.68 | 19.64 | 22.35 |

Interpretation:

- There was no meaningful drop in `model_load_seconds` between run 1 and run 2.
- In the current packaged design, each invocation launches a fresh Python
  process and constructs a new `WhisperModel(...)`, so per-run model
  initialization cost is expected.
- The current measurements do not show a first-run-only download penalty inside
  this already-provisioned runtime. They do show a stable per-invocation model
  load cost of about 4.6 seconds for `large-v3`.
- This issue therefore resolves to documentation and measurement, not to an
  immediate correctness bug. Any future work to keep the model warm across runs
  would be a separate architecture/performance enhancement.

Measurement note:

- During this check, the remote `run-node-whisper-job.ps1` invocation returned
  exit code `0` but an empty stdout payload over SSH, while still producing the
  expected remote `transcript.json` artifact. Timing evidence above was read
  from that generated JSON artifact after successful remote completion.
