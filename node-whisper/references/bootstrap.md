# Node Whisper Bootstrap

## Scope

Use this reference when the Windows node needs to be reached, inspected,
bootstrapped, or repaired behind the packaged entrypoint.

The shell wrappers read machine-specific values from `{baseDir}/.env` at the
skill root. Keep the actual file local-only and publish only `.env.example`.
That local config may include:

- `NODE_WHISPER_REMOTE_USER`
- `NODE_WHISPER_REMOTE_HOST`
- `NODE_WHISPER_SSH_KEY`
- `NODE_WHISPER_SSH_PUBLIC_KEY`

## Bootstrap Order

1. expose a usable Windows SSH entry point
2. probe the remote environment
3. install the `faster-whisper` runtime under the fixed root
4. run the CUDA smoke test
5. run a real media transcription through the packaged wrapper

The packaged wrapper now composes these checks automatically. Read this file when
you need to diagnose a failed probe, install, or smoke gate in detail.

## SSH Enablement

Install OpenSSH Server on Windows in elevated PowerShell:

```powershell
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

If needed:

```powershell
dism /online /Get-Capabilities | findstr /I OpenSSH.Server
dism /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0
```

Start the service and enable autostart:

```powershell
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Get-Service sshd
```

Allow inbound TCP/22:

```powershell
New-NetFirewallRule -Name sshd-in-tcp -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

Install the Linux-side SSH key on Windows with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-node-whisper-ssh-key.ps1
```

The script resolves the public key in this order:

1. `-PublicKey`
2. `NODE_WHISPER_SSH_PUBLIC_KEY` from the environment
3. `NODE_WHISPER_SSH_PUBLIC_KEY` from the skill-root `.env`

Validate reachability from Linux:

```bash
nc -zv -w 3 <windows_host> 22
ssh -i ~/.ssh/node_whisper_win -o StrictHostKeyChecking=accept-new <windows_user>@<windows_host> hostname
```

SSH is for bootstrap, diagnostics, repair, and the current packaged Windows
execution path in this draft. Keep it
available even if a later node-host execution path is added.

## Environment Probe

Checks:

- `uv`
- `python` / `py`
- `ffmpeg`
- `whisper`
- `nvidia-smi`

Run from Linux:

```bash
chmod +x ./scripts/run-node-whisper-env-probe.sh
./scripts/run-node-whisper-env-probe.sh
```

Optional arguments:

```bash
./scripts/run-node-whisper-env-probe.sh <windows_user> <windows_host>
```

If arguments are omitted, the wrapper falls back to the skill-root `.env`.

Run directly on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\probe-node-whisper-env.ps1
```

Minimum pass criteria:

1. `uv` is available
2. `nvidia-smi` is available
3. either `python` or `py` is available

`ffmpeg` and the Whisper runtime must still be resolved before final execution, but they are not required to conclude that the host is worth bootstrapping.
The packaged wrapper treats missing `ffmpeg` as a repair blocker because the
current install path depends on it.

## Runtime Install

Run from Linux:

```bash
chmod +x ./scripts/run-node-whisper-install.sh
./scripts/run-node-whisper-install.sh
```

If host arguments are omitted, the wrapper falls back to the skill-root `.env`.

This uploads and runs `scripts/install-node-whisper-faster-whisper.ps1`, which:

- verifies `uv` and `ffmpeg`
- creates the runtime directory
- creates `.venv` with `uv`
- installs `faster-whisper`

Expected install state:

- `E:\Projects\node-whisper-runtime\.venv`

## Smoke Test

Run from Linux:

```bash
chmod +x ./scripts/run-node-whisper-smoke.sh
./scripts/run-node-whisper-smoke.sh
```

If host arguments are omitted, the wrapper falls back to the skill-root `.env`.

Expected JSON contains at least:

- `ok: true`
- `stage: "done"`
- `model: "tiny"`
- `device: "cuda"`

Common failure cases:

- `uv` missing
- `ffmpeg` missing
- incomplete CUDA libraries
- GPU visible in `nvidia-smi`, but `WhisperModel(..., device="cuda")` still fails

The packaged wrapper uses the smoke test as the confidence gate after install or
repair.

## Real Media Validation

For a heavier confidence check, run the packaged entrypoint against a local
media file of your own after probe, install, and smoke have all passed.

## Diagnostic Rule

Separate these layers during failure analysis:

1. SSH reachability
2. Windows toolchain availability
3. runtime install health
4. CUDA inference health
5. real-audio transcription behavior
