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


if __name__ == "__main__":
    unittest.main()
