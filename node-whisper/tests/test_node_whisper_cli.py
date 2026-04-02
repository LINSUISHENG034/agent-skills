#!/usr/bin/env python3
import json
import os
import subprocess
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ORCHESTRATOR = ROOT / "scripts" / "node_whisper_orchestrate.sh"
ENV_FILE = ROOT / ".env"
ENV_EXAMPLE_FILE = ROOT / ".env.example"
SSH_KEY_INSTALL_SCRIPT = ROOT / "scripts" / "install-node-whisper-ssh-key.ps1"
SKILL_FILE = ROOT / "SKILL.md"
BOOTSTRAP_REF = ROOT / "references" / "bootstrap.md"
BROKEN_VALIDATION_SCRIPT = ROOT / "scripts" / "run-node-whisper-large-v3-validation.sh"


class NodeWhisperCliTests(unittest.TestCase):
    def run_orchestrator(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(ORCHESTRATOR), *args],
            text=True,
            capture_output=True,
            cwd=ROOT,
            env=env,
        )

    def write_executable(self, path: Path, contents: str) -> None:
        path.write_text(contents, encoding="utf-8")
        path.chmod(0o755)

    @contextmanager
    def temporary_skill_env(self, contents: str):
        original = ENV_FILE.read_text(encoding="utf-8") if ENV_FILE.exists() else None
        ENV_FILE.write_text(contents, encoding="utf-8")
        try:
            yield
        finally:
            if original is None:
                ENV_FILE.unlink(missing_ok=True)
            else:
                ENV_FILE.write_text(original, encoding="utf-8")

    @contextmanager
    def stubbed_orchestrator_runtime(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            media = root / "clip.wav"
            media.write_text("fake media placeholder", encoding="utf-8")
            ssh_key = root / "node_whisper_test_key"
            ssh_key.write_text("not-a-real-key", encoding="utf-8")

            validate_stub = root / "validate.sh"
            ready_stub = root / "ready.sh"
            stage_stub = root / "stage.sh"
            fetch_stub = root / "fetch.sh"
            error_map_stub = root / "error_map.py"
            ssh_stub = root / "ssh"

            self.write_executable(
                validate_stub,
                """#!/usr/bin/env bash
set -euo pipefail
quiet=0
want_json=0
timestamps=0
output_dir=""
input_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet)
      quiet=1
      shift
      ;;
    --json)
      want_json=1
      shift
      ;;
    --timestamps)
      timestamps=1
      want_json=1
      shift
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --model|--language|--node|--transport)
      shift 2
      ;;
    --force-repair|--dry-run)
      shift
      ;;
    -*)
      shift
      ;;
    *)
      if [[ -z "$input_path" ]]; then
        input_path="$1"
      fi
      shift
      ;;
  esac
done
if [[ -z "$output_dir" ]]; then
  output_dir="$(dirname "$input_path")"
fi
input_name="$(basename "$input_path")"
input_stem="${input_name%.*}"
python3 - <<'PY' "$input_path" "$input_name" "$input_stem" "$output_dir" "$want_json" "$timestamps" "$quiet"
import json
import sys

input_path, input_name, input_stem, output_dir, want_json, timestamps, quiet = sys.argv[1:]
payload = {
    "ok": True,
    "stage": "input",
    "input_path": input_path,
    "input_name": input_name,
    "input_stem": input_stem,
    "input_extension": ".wav",
    "media_kind": "audio",
    "output_format": "text+json" if want_json == "1" else "text",
    "model": "large-v3",
    "language": None,
    "node_name": None,
    "output_dir": output_dir,
    "transport": "ssh",
    "want_json": want_json == "1",
    "timestamps": timestamps == "1",
    "quiet": quiet == "1",
    "force_repair": False,
    "dry_run": False,
}
print(json.dumps(payload))
PY
""",
            )

            self.write_executable(
                ready_stub,
                """#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import json
print(json.dumps({
    "ok": True,
    "stage": "ready",
    "transport": "ssh",
    "node_name": None,
    "remote_user": "stub-user",
    "remote_host": "stub-host",
    "runtime_dir": "C:/node-whisper-runtime",
    "runtime_repaired": False,
}))
PY
""",
            )

            self.write_executable(
                stage_stub,
                """#!/usr/bin/env bash
set -euo pipefail
output_dir=""
input_stem=""
want_json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --input-stem)
      input_stem="${2:-}"
      shift 2
      ;;
    --want-json)
      want_json=1
      shift
      ;;
    --input|--transport)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
python3 - <<'PY' "$output_dir" "$input_stem" "$want_json"
import json
import sys

output_dir, input_stem, want_json = sys.argv[1:]
payload = {
    "job_id": "job-123",
    "runtime_dir": "C:/node-whisper-runtime",
    "remote_input_path": f"C:/node-whisper-runtime/jobs/{input_stem}/input.wav",
    "remote_text_out": f"C:/node-whisper-runtime/jobs/{input_stem}/transcript.txt",
    "remote_json_out": f"C:/node-whisper-runtime/jobs/{input_stem}/transcript.json" if want_json == "1" else None,
    "output_dir": output_dir,
    "input_stem": input_stem,
    "want_json": want_json == "1",
}
print(json.dumps(payload))
PY
""",
            )

            self.write_executable(
                fetch_stub,
                """#!/usr/bin/env bash
set -euo pipefail
remote_text_out=""
output_dir=""
input_stem=""
remote_json_out=""
want_json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-text-out)
      remote_text_out="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --input-stem)
      input_stem="${2:-}"
      shift 2
      ;;
    --remote-json-out)
      remote_json_out="${2:-}"
      shift 2
      ;;
    --want-json)
      want_json=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$output_dir"
local_text_out="${output_dir}/${input_stem}.node-whisper.txt"
printf 'stub transcript\n' > "$local_text_out"
local_json_out=""
if [[ "$want_json" -eq 1 ]]; then
  local_json_out="${output_dir}/${input_stem}.node-whisper.json"
  printf '{"ok": true}\n' > "$local_json_out"
fi
python3 - <<'PY' "$local_text_out" "$local_json_out" "$want_json" "$remote_text_out" "$remote_json_out"
import json
import sys

local_text_out, local_json_out, want_json, remote_text_out, remote_json_out = sys.argv[1:]
payload = {
    "stage": "fetch",
    "remote_text_out": remote_text_out,
    "remote_json_out": remote_json_out or None,
    "local_text_out": local_text_out,
    "local_json_out": local_json_out if want_json == "1" else None,
}
print(json.dumps(payload))
PY
""",
            )

            self.write_executable(
                error_map_stub,
                """#!/usr/bin/env python3
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("--stage", required=True)
parser.add_argument("--error-code", required=True)
parser.add_argument("--message", required=True)
parser.add_argument("--exit-code", required=True, type=int)
args = parser.parse_args()
print(json.dumps({
    "ok": False,
    "stage": args.stage,
    "error_code": args.error_code,
    "message": args.message,
    "exit_code": args.exit_code,
}))
""",
            )

            self.write_executable(
                ssh_stub,
                """#!/usr/bin/env bash
set -euo pipefail
printf '{"ok": true, "stage": "done"}\n'
""",
            )

            env = os.environ.copy()
            env["PATH"] = f"{root}:{env.get('PATH', '')}"
            env["NODE_WHISPER_ENV_FILE"] = str(root / "missing.env")
            env["NODE_WHISPER_REMOTE_USER"] = "stub-user"
            env["NODE_WHISPER_REMOTE_HOST"] = "stub-host"
            env["NODE_WHISPER_SSH_KEY"] = str(ssh_key)
            env["NODE_WHISPER_VALIDATE_INPUT_HELPER"] = str(validate_stub)
            env["NODE_WHISPER_REQUIRE_READY_HELPER"] = str(ready_stub)
            env["NODE_WHISPER_STAGE_MEDIA_HELPER"] = str(stage_stub)
            env["NODE_WHISPER_FETCH_RESULTS_HELPER"] = str(fetch_stub)
            env["NODE_WHISPER_ERROR_MAP_HELPER"] = str(error_map_stub)

            yield media, env

    def test_missing_input_path_returns_input_not_found(self) -> None:
        result = self.run_orchestrator("/tmp/definitely-missing-node-whisper-input.wav")

        self.assertNotEqual(result.returncode, 0)
        payload = json.loads(result.stderr.strip())
        self.assertEqual(payload["error_code"], "input_not_found")
        self.assertEqual(payload["stage"], "input")

    def test_unsupported_extension_returns_unsupported_input_type(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            bogus = Path(tmpdir) / "note.txt"
            bogus.write_text("not media", encoding="utf-8")

            result = self.run_orchestrator(str(bogus))

        self.assertNotEqual(result.returncode, 0)
        payload = json.loads(result.stderr.strip())
        self.assertEqual(payload["error_code"], "unsupported_input_type")
        self.assertEqual(payload["stage"], "input")

    def test_dry_run_loads_transport_and_node_name_from_skill_root_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            media = Path(tmpdir) / "clip.mp3"
            media.write_text("fake media placeholder", encoding="utf-8")

            with self.temporary_skill_env(
                "NODE_WHISPER_TRANSPORT=node-host\nNODE_WHISPER_NODE_NAME=lab-gpu\n"
            ):
                env = os.environ.copy()
                for key in (
                    "NODE_WHISPER_TRANSPORT",
                    "NODE_WHISPER_NODE_NAME",
                    "NODE_WHISPER_REMOTE_USER",
                    "NODE_WHISPER_REMOTE_HOST",
                    "NODE_WHISPER_SSH_KEY",
                    "SSH_KEY",
                ):
                    env.pop(key, None)
                result = self.run_orchestrator(str(media), "--dry-run", env=env)

        self.assertEqual(result.returncode, 0)
        payload = json.loads(result.stdout.strip())
        self.assertEqual(payload["transport"], "node-host")
        self.assertEqual(payload["node_name"], "lab-gpu")

    def test_env_example_exposes_ssh_public_key_variable(self) -> None:
        example = ENV_EXAMPLE_FILE.read_text(encoding="utf-8")
        self.assertIn("NODE_WHISPER_SSH_PUBLIC_KEY=", example)

    def test_install_script_does_not_embed_real_ssh_public_key(self) -> None:
        script = SSH_KEY_INSTALL_SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("ssh-ed25519 AAAA", script)
        self.assertIn("NODE_WHISPER_SSH_PUBLIC_KEY", script)

    def test_publishable_surface_has_no_stale_fixture_validation_references(self) -> None:
        self.assertFalse(BROKEN_VALIDATION_SCRIPT.exists())
        skill = SKILL_FILE.read_text(encoding="utf-8")
        bootstrap = BOOTSTRAP_REF.read_text(encoding="utf-8")
        for text in (skill, bootstrap):
            self.assertNotIn("run-node-whisper-large-v3-validation.sh", text)
            self.assertNotIn("fixtures/", text)
            self.assertNotIn("validation/", text)
            self.assertNotIn("192.168.0.193", text)

    def test_progress_markers_are_emitted_to_stderr_by_default(self) -> None:
        with self.stubbed_orchestrator_runtime() as (media, env):
            result = self.run_orchestrator(str(media), env=env)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "stub transcript\n")
        self.assertIn("node-whisper[validate]:", result.stderr)
        self.assertIn("node-whisper[ready]:", result.stderr)
        self.assertIn("node-whisper[stage]:", result.stderr)
        self.assertIn("node-whisper[transcribe]:", result.stderr)
        self.assertIn("node-whisper[fetch]:", result.stderr)
        self.assertIn("node-whisper: node=stub-host model=large-v3", result.stderr)

    def test_quiet_mode_suppresses_progress_markers(self) -> None:
        with self.stubbed_orchestrator_runtime() as (media, env):
            result = self.run_orchestrator(str(media), "--quiet", env=env)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "stub transcript\n")
        self.assertNotIn("node-whisper[validate]:", result.stderr)
        self.assertNotIn("node-whisper[ready]:", result.stderr)
        self.assertNotIn("node-whisper[stage]:", result.stderr)
        self.assertNotIn("node-whisper[transcribe]:", result.stderr)
        self.assertNotIn("node-whisper[fetch]:", result.stderr)
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
