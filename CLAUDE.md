# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A personal skill repository for OpenClaw agent workflows. Each "skill" is a self-contained module an AI agent invokes to perform specialized tasks (browser automation, host diagnostics, audio transcription, device control). Skills are authored following Anthropic's skill-authoring conventions.

## Repository Structure

```
<skill-name>/              # Published skills at root (portable, redistributable)
  SKILL.md                 # Skill definition: YAML frontmatter (name, description/trigger) + workflow body
  scripts/                 # Executable scripts (bash, Python)
  references/              # Background docs, troubleshooting, detailed context
  agents/openai.yaml       # UI metadata for OpenClaw agent integration

drafts/<skill-name>/       # Unpublished/experimental skills (gitignored)
docs/references/           # Tracked maintainer reference material
docs/plans/                # Local-only plans (untracked, never commit)
docs/issues/               # Local-only debug notes (untracked, never commit)
```

## Skill Anatomy

Every SKILL.md follows this structure:
- **YAML frontmatter**: `name` and `description` (the description is the trigger condition)
- **Markdown body**: When To Use, Do Not Use, Core Rules, Preferred Entry Point (using `{baseDir}` placeholder), Workflow steps, Key Files, References

The `{baseDir}` placeholder resolves at runtime to the skill's installation directory.

## Key Conventions

- **Draft → Root promotion**: Build new skills under `drafts/`. Promote to root only when publishable.
- **Progressive disclosure**: Short frontmatter → focused SKILL.md → detailed `references/`.
- **Executable over prose**: Prefer scripts in `scripts/` over repeating command blocks in Markdown.
- **Composability**: Skills compose with other skills, MCP tools, and external companions (e.g., `agent-browser`).
- **Portability**: No hardcoded machine-specific paths, accounts, or secrets in published skills.
- **Scope discipline**: Don't let a skill grow into general agent logic. Browser-session handles sessions, not downstream content extraction.

## Git Rules

- Use targeted `git add path/to/file` — never `git add .` with mixed local/publishable work.
- Check `git status --short` before every commit.
- `docs/plans/` and `docs/issues/` must never be staged or committed.
- Local secrets, runtime state, `.env` files stay untracked.
- If local-only files are accidentally tracked: `git rm --cached <path>`.

## Testing

No unified test framework. Testing is skill-specific:

- **ubuntu-browser-session**: Bash test scripts (`scripts/test_*.sh`) using `set -euo pipefail` assertions, plus `scripts/test_cdp_helpers.py` for Python CDP helpers.
- **drafts/wechat-topic-research**: pytest-style Python tests (`tests/test_*.py`) with a custom `tests/run_all.py` runner and `tests/conftest.py` for path setup. Can run without pytest installed.

Run bash tests directly: `bash <skill>/scripts/test_<name>.sh`
Run Python tests: `python3 <skill>/scripts/test_<name>.py` or `python3 <skill>/tests/run_all.py`

## OpenClaw Verification

When validating skills through OpenClaw:
- Verify the managed copy under `~/.openclaw/workspace/skills/<skill-slug>/` — the agent may not execute from the repo draft.
- Use `openclaw agent --agent main --json --message "..."` for machine-readable results.
- Inspect session logs at `~/.openclaw/agents/main/sessions/*.jsonl` to confirm which skill/script ran.

## Languages & Technologies

- **Bash**: Primary for ubuntu-browser-session and deployment-host-diagnostics scripts
- **Python 3**: CDP tools (cdp-eval.py, cdp-snapshot.py), transcription, research skills
- **Chrome DevTools Protocol (CDP)**: Page inspection, navigation, content extraction in browser session skill
- **X11/Xvfb + x11vnc + websockify + noVNC**: Virtual display stack for headless browser with remote access

## Release Checklist

Before push, verify:
1. No `docs/plans/` or `docs/issues/` files in staged changes
2. Root-level skills are complete and publishable
3. Secrets and host-specific notes remain untracked
