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
