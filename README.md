# agent-skills

Personal skill repository for agent workflows, browser automation, device control, and media tooling.

## Repository Layout

Each skill lives in its own directory and typically contains:

- `SKILL.md`
- `references/`
- `scripts/`
- optional UI metadata such as `agents/openai.yaml`

Published skills live at the repository root. Unfinished skills stay under `drafts/` and are ignored by git until they are ready to be promoted.
Maintainer-facing reference material lives under `docs/`.

## Current Skills

- `deployment-host-diagnostics`
  - Host-side diagnostics for OpenClaw deployments using live command-backed evidence and layered troubleshooting.
- `host-assisted-browser-login`
  - Headless Linux login bootstrap with user-assisted noVNC access for cookies, OAuth, CAPTCHA, and 2FA.
- `qwen3-asr-transcribe`
  - Local transcription workflow using a bundled Qwen3 ASR runtime.

## Draft Skills

Drafts are kept under `drafts/` and are intentionally excluded from version control.

- Move an unfinished skill into `drafts/` to keep it in the same workspace without publishing it.
- Promote a skill by moving it from `drafts/<skill-name>/` to the repository root and removing any local-only files.
- Root-level skills should be publishable; `drafts/` skills may be incomplete, experimental, or locally tied to one environment.

## Documentation

Use `docs/` for maintainer references, authoring notes, and example material that should not be confused with publishable skills.

- `docs/references/`
  - External guides, archived references, and canonical background material
- `docs/plans/`
  - Local working plans for repository maintenance; ignored from version control

## Publishing Rules

Before pushing publicly, keep this repository limited to material that can be safely redistributed:

- Publish skills, helper scripts, and maintainer-written documentation
- Keep secrets, local runtimes, private keys, and environment files untracked
- Keep unfinished skills under `drafts/`
- Keep third-party reference documents untracked unless redistribution rights are clear
- Prefer README notes that explain an external reference over committing the full source document

## External Companion Skills

This repository may interoperate with skills installed from other sources, but it does not vendor or publish those third-party skills.

Example:

- `agent-browser`
  - Install from its upstream distribution if you want a general browser-interaction companion for rendered pages, clicks, typing, screenshots, and visual verification.

Install command:

```bash
npx clawhub@latest install agent-browser
```

## Skill Handoff

`host-assisted-browser-login` is designed to work with an external browser-interaction skill such as `agent-browser`:

1. If a usable interactive browser session already exists, use your installed browser-interaction skill.
2. If the host is headless and the task is blocked on login, cookies, CAPTCHA, or 2FA, use `host-assisted-browser-login` first.
3. After the host-side authenticated session is established, switch back to the external browser-interaction skill for normal page interaction and verification.
4. When the saved profile is sufficient, stop the host-assisted stack to save resources.

Quick rule:

- "I need to interact with a web page" -> use an installed browser-interaction skill such as `agent-browser`
- "I need to establish a host-side logged-in browser first" -> `host-assisted-browser-login`

## Local-Only Files

This repository intentionally ignores local secrets and runtime artifacts, including:

- ADB private keys
- `.env` and `.asr_env`
- `.venv`
- Python cache files
- local copies of third-party reference documents

If a skill needs local credentials or runtime state, keep them beside the skill but outside version control.

## Maintenance Notes

- Keep boundaries explicit. Avoid duplicating the same workflow in multiple skills.
- When one local skill depends on an external companion skill, document the handoff in the local skill and in this repository README.
- Prefer portable placeholders or local configuration files over hardcoded secrets.
- Use `drafts/` instead of ad hoc `.gitignore` entries when a whole skill is not ready for release.
