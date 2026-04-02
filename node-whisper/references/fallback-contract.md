# Explicit Fallback Contract

`node-whisper` keeps the Windows GPU path as the primary execution route.
Fallback is opt-in and exists only to provide a clearer operator choice when the
remote node cannot pass the ready gate.

## Trigger Rule

Fallback is attempted only when all of the following are true:

- the caller supplied `--fallback-provider <name>`
- the packaged workflow failed in the `ready` stage
- the normalized error code is one of:
  - `node_unreachable`
  - `node_runtime_repair_failed`

If no provider was enabled, the wrapper returns the original structured error
with an added message that no fallback provider was enabled.

## Current Provider

- `http-generic`

This is a local adapter module, not a dependency on another skill. The intent is
to keep provider replacement isolated to one module boundary.

## Provider Input Contract

The fallback runner receives:

- local input media path
- local output directory
- input stem
- requested model name
- optional language
- optional config file path
- optional reason fields (`reason_stage`, `reason_code`)

## Provider Success Contract

On success, the provider returns JSON with:

- `ok: true`
- `stage: "fallback"`
- `engine: "fallback"`
- `provider`
- `local_text_out`
- `local_json_out` when JSON output was requested
- `language` when known
- `duration` when known
- `total_seconds`

The provider must write the transcript text to `local_text_out`.

## Provider Failure Contract

On failure, the provider prints structured JSON to stderr with:

- `ok: false`
- `stage`
- `error_code`
- `message`

## http-generic Configuration

The first provider supports a generic multipart HTTP POST adapter.

Configuration can come from:

- `--fallback-config <path>` JSON
- environment variables

Supported environment variables:

- `NODE_WHISPER_FALLBACK_HTTP_URL`
- `NODE_WHISPER_FALLBACK_HTTP_HEADERS_JSON`
- `NODE_WHISPER_FALLBACK_HTTP_EXTRA_FORM_JSON`
- `NODE_WHISPER_FALLBACK_HTTP_TIMEOUT_SECONDS`
- `NODE_WHISPER_FALLBACK_HTTP_FILE_FIELD`
- `NODE_WHISPER_FALLBACK_HTTP_MODEL_FIELD`
- `NODE_WHISPER_FALLBACK_HTTP_LANGUAGE_FIELD`
- `NODE_WHISPER_FALLBACK_HTTP_TEXT_FIELD`
- `NODE_WHISPER_FALLBACK_HTTP_LANGUAGE_RESPONSE_FIELD`
- `NODE_WHISPER_FALLBACK_HTTP_DURATION_FIELD`
- `NODE_WHISPER_FALLBACK_HTTP_SEGMENTS_FIELD`

Minimal JSON config example:

```json
{
  "url": "https://example.invalid/transcriptions"
}
```

More explicit example:

```json
{
  "url": "https://example.invalid/transcriptions",
  "headers": {
    "Authorization": "Bearer YOUR_TOKEN"
  },
  "form_fields": {
    "response_format": "json"
  },
  "file_field": "file",
  "model_field": "model",
  "language_field": "language",
  "text_field": "text",
  "language_response_field": "language",
  "duration_field": "duration"
}
```
