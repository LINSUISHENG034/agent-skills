#!/usr/bin/env python3
import argparse
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--input-stem", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--model", default="large-v3")
    parser.add_argument("--language", default="")
    parser.add_argument("--config")
    parser.add_argument("--want-json", action="store_true")
    parser.add_argument("--timestamps", action="store_true")
    parser.add_argument("--reason-stage", default="")
    parser.add_argument("--reason-code", default="")
    return parser.parse_args()


def fail(stage: str, error_code: str, message: str, exit_code: int = 1, *, details: dict | None = None) -> int:
    payload: dict[str, object] = {
        "ok": False,
        "stage": stage,
        "error_code": error_code,
        "message": message,
    }
    if details:
        payload["details"] = details
    print(json.dumps(payload, ensure_ascii=False), file=sys.stderr)
    return exit_code


def parse_json_env(name: str) -> dict:
    value = os.environ.get(name, "").strip()
    if not value:
        return {}
    try:
        loaded = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{name} is not valid JSON: {exc}") from exc
    if not isinstance(loaded, dict):
        raise ValueError(f"{name} must be a JSON object")
    return loaded


def resolve_path(data: dict, dotted_field: str):
    value = data
    for part in dotted_field.split("."):
        if not isinstance(value, dict) or part not in value:
            raise KeyError(dotted_field)
        value = value[part]
    return value


def build_config(args: argparse.Namespace) -> dict:
    config: dict[str, object] = {}
    if args.config:
        config = json.loads(Path(args.config).read_text(encoding="utf-8"))
        if not isinstance(config, dict):
            raise ValueError("fallback config file must contain a JSON object")

    headers = dict(config.get("headers") or {})
    headers.update(parse_json_env("NODE_WHISPER_FALLBACK_HTTP_HEADERS_JSON"))

    form_fields = dict(config.get("form_fields") or {})
    form_fields.update(parse_json_env("NODE_WHISPER_FALLBACK_HTTP_EXTRA_FORM_JSON"))

    return {
        "url": config.get("url") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_URL", ""),
        "method": str(config.get("method") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_METHOD", "POST")).upper(),
        "timeout_seconds": float(config.get("timeout_seconds") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_TIMEOUT_SECONDS", "600")),
        "headers": headers,
        "form_fields": form_fields,
        "file_field": config.get("file_field") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_FILE_FIELD", "file"),
        "model_field": config.get("model_field") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_MODEL_FIELD", "model"),
        "language_field": config.get("language_field") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_LANGUAGE_FIELD", "language"),
        "text_field": config.get("text_field") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_TEXT_FIELD", "text"),
        "language_response_field": config.get("language_response_field") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_LANGUAGE_RESPONSE_FIELD", "language"),
        "duration_field": config.get("duration_field") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_DURATION_FIELD", "duration"),
        "segments_field": config.get("segments_field") or os.environ.get("NODE_WHISPER_FALLBACK_HTTP_SEGMENTS_FIELD", "segments"),
    }


def build_multipart_body(fields: dict[str, str], file_field: str, file_path: Path) -> tuple[bytes, str]:
    boundary = f"----node-whisper-{uuid.uuid4().hex}"
    body = bytearray()
    for key, value in fields.items():
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode("utf-8"))
        body.extend(str(value).encode("utf-8"))
        body.extend(b"\r\n")

    mime = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(
        f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'.encode("utf-8")
    )
    body.extend(f"Content-Type: {mime}\r\n\r\n".encode("utf-8"))
    body.extend(file_path.read_bytes())
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode("utf-8"))
    return bytes(body), boundary


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_dir = Path(args.output_dir)

    if not input_path.exists():
        return fail("fallback", "input_not_found", f"Fallback input media not found: {input_path}", 2)

    try:
        config = build_config(args)
    except Exception as exc:
        return fail("fallback", "fallback_invalid_config", str(exc), 2)

    if not config["url"]:
        return fail(
            "fallback",
            "fallback_missing_configuration",
            "The http-generic fallback provider requires a URL via --fallback-config or NODE_WHISPER_FALLBACK_HTTP_URL.",
            3,
        )
    if config["method"] != "POST":
        return fail("fallback", "fallback_invalid_config", "The http-generic fallback provider currently supports only POST.", 2)

    fields = dict(config["form_fields"])
    if config["model_field"]:
        fields[str(config["model_field"])] = args.model
    if args.language and config["language_field"]:
        fields[str(config["language_field"])] = args.language

    try:
        request_body, boundary = build_multipart_body(fields, str(config["file_field"]), input_path)
    except Exception as exc:
        return fail("fallback", "fallback_request_build_failed", str(exc), 2)

    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    headers.update({str(k): str(v) for k, v in dict(config["headers"]).items()})
    request = urllib.request.Request(
        url=str(config["url"]),
        data=request_body,
        headers=headers,
        method="POST",
    )

    started_at = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=float(config["timeout_seconds"])) as response:
            raw_body = response.read().decode("utf-8")
            status_code = getattr(response, "status", 200)
    except urllib.error.HTTPError as exc:
        return fail(
            "fallback",
            "fallback_provider_http_error",
            f"http-generic provider returned HTTP {exc.code}",
            12,
            details={"status": exc.code, "body": exc.read().decode('utf-8', errors='replace')},
        )
    except urllib.error.URLError as exc:
        return fail("fallback", "fallback_provider_unreachable", f"http-generic provider request failed: {exc.reason}", 11)

    elapsed = time.perf_counter() - started_at
    try:
        response_json = json.loads(raw_body)
    except json.JSONDecodeError as exc:
        return fail(
            "fallback",
            "fallback_invalid_response",
            f"http-generic provider returned non-JSON output: {exc}",
            12,
            details={"status": status_code, "body": raw_body[:500]},
        )

    try:
        transcript_text = resolve_path(response_json, str(config["text_field"]))
    except KeyError:
        return fail(
            "fallback",
            "fallback_invalid_response",
            f"http-generic provider response did not contain transcript field '{config['text_field']}'.",
            12,
            details={"status": status_code, "body": response_json},
        )

    language = None
    try:
        language = resolve_path(response_json, str(config["language_response_field"]))
    except KeyError:
        language = None

    duration = None
    try:
        duration = resolve_path(response_json, str(config["duration_field"]))
    except KeyError:
        duration = None

    segments = None
    try:
        segments = resolve_path(response_json, str(config["segments_field"]))
    except KeyError:
        segments = None

    output_dir.mkdir(parents=True, exist_ok=True)
    local_text_out = output_dir / f"{args.input_stem}.node-whisper.txt"
    local_text_out.write_text(str(transcript_text).strip(), encoding="utf-8")

    local_json_out = None
    if args.want_json or args.timestamps:
        local_json_out = output_dir / f"{args.input_stem}.node-whisper.json"
        sidecar = {
            "ok": True,
            "stage": "fallback",
            "engine": "fallback",
            "provider": args.provider,
            "audio": str(input_path),
            "model": args.model,
            "language": language,
            "duration": duration,
            "total_seconds": elapsed,
            "text_out": str(local_text_out),
            "provider_response": response_json,
        }
        if segments is not None:
            sidecar["segments"] = segments
        local_json_out.write_text(json.dumps(sidecar, ensure_ascii=False, indent=2), encoding="utf-8")

    payload = {
        "ok": True,
        "stage": "fallback",
        "engine": "fallback",
        "provider": args.provider,
        "local_text_out": str(local_text_out),
        "local_json_out": str(local_json_out) if local_json_out else None,
        "language": language,
        "duration": duration,
        "total_seconds": elapsed,
        "reason_stage": args.reason_stage or None,
        "reason_code": args.reason_code or None,
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
