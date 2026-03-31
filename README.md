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
Local-only third-party skill sources live under `third_party/`.

## Current Skills

- `ubuntu-browser-session`
  - Standalone Ubuntu Server browser workflow for protected sites, live session reuse, challenge recovery, and noVNC-assisted session capture.
- `deployment-host-diagnostics`
  - Host-side diagnostics for OpenClaw deployments using live command-backed evidence and layered troubleshooting.
- `qwen3-asr-transcribe`
  - Local transcription workflow using a bundled Qwen3 ASR runtime.
- `markdown-mobile-export`
  - Faithful local Markdown to mobile long-image export with HTML sidecar output and browser-backed full-page capture.
- `node-whisper`
  - SSH-backed LAN Windows GPU transcription workflow for local audio or video files, with automatic runtime probe and repair.

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

## Third-Party References

Use `third_party/` for local-only third-party skill material that you want to inspect over time without vendoring it into this repository.

- `third_party/repos/`
  - Full upstream repositories cloned locally for update tracking
- `third_party/imports/`
  - Single copied skills or partial references kept only as local authoring input

Keep all contents under `third_party/` ignored by git by default. Use the repository name directly under `third_party/repos/`, for example `third_party/repos/baoyu-skills/`. For copied or partial references under `third_party/imports/`, preserve author or organization names when known, for example `third_party/imports/JimLiu/some-single-skill/` or `third_party/imports/unknown/copied-skill/`.

Maintenance commands:

```bash
# Fetch remote updates for every tracked third-party repo without changing local checkouts
bash scripts/update-third-party-repos.sh

# Fast-forward local third-party checkouts only when you explicitly want to sync them
bash scripts/update-third-party-repos.sh --pull
```

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

`ubuntu-browser-session` is the canonical public name for the former `agent-browser-ubuntu-server` skill. It owns host-side browser session discovery, reuse, assisted login, and page verification inside one workflow.

Use an external browser-interaction companion such as `agent-browser` only when:

1. A usable authenticated browser session already exists.
2. The remaining work is ordinary page interaction, screenshots, or DOM inspection.
3. You do not need session recovery, assisted login, or host-side browser stack repair.

Quick rule:

- "I need to interact with a web page" -> use an installed browser-interaction skill such as `agent-browser`
- "I need to establish or recover a host-side logged-in browser first" -> `ubuntu-browser-session`

## Local-Only Files

This repository intentionally ignores local secrets and runtime artifacts, including:

- ADB private keys
- `.env` and `.asr_env`
- `.venv`
- Python cache files
- local copies of third-party reference documents
- local third-party skill repositories and copied skill references

If a skill needs local credentials or runtime state, keep them beside the skill but outside version control.

## Maintenance Notes

- Keep boundaries explicit. Avoid duplicating the same workflow in multiple skills.
- When one local skill depends on an external companion skill, document the handoff in the local skill and in this repository README.
- Prefer portable placeholders or local configuration files over hardcoded secrets.
- Use `drafts/` instead of ad hoc `.gitignore` entries when a whole skill is not ready for release.
