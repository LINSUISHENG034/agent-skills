# Repository Working Rules

This repository is for publishable skills plus local-only development support files.

## Skill Development Scope

- Build new or incomplete skills under `drafts/`.
- Promote a skill to the repository root only when it is ready to publish.
- Keep published root-level skills portable and redistributable.
- Reuse existing scripts and references where practical instead of duplicating workflows across skills.

## Skill Authoring Principles

- Start from 2-3 concrete use cases before writing the skill structure or scripts.
- Keep each skill scoped to the problem it is supposed to solve; do not let a browser-session or environment skill grow into general downstream task logic that belongs to the agent.
- When a skill's purpose is session reuse, host access, or environment setup, evaluate it on whether it preserves the correct execution context and access path, not on whether the agent can always complete later site-specific content extraction.
- Use progressive disclosure:
  - keep YAML frontmatter short and focused on trigger conditions
  - keep `SKILL.md` focused on workflow and decision rules
  - move detailed background, examples, and deep references into `references/`
- Prefer executable workflows in `scripts/` over long manual command blocks repeated in Markdown.
- Design skills to compose with other skills, MCP tools, and external companion skills instead of assuming they run alone.
- Keep published skills portable across hosts and agent environments; avoid hardcoded machine-specific paths, accounts, or local secrets.
- Validate the smallest end-to-end workflow before promoting a draft skill to the repository root.

## Local Development Docs

The following paths are local working material for skill development and must stay out of version control:

- `docs/plans/`
- `docs/issues/`

Rules:

- Store design notes, implementation plans, and issue investigation notes only under those directories.
- Do not `git add -f` files from those directories.
- Do not commit or push files from those directories to the remote repository.
- If a document becomes useful for published consumers, rewrite it into a skill README, `SKILL.md`, or a publishable reference under the skill directory instead of promoting the local note directly.

## Git Rules

- Prefer targeted adds such as `git add path/to/file`.
- Do not use broad staging commands such as `git add .` for mixed local and publishable work.
- Check `git status --short` before every commit.
- Keep local-only notes untracked.
- If a local-only file is accidentally tracked, remove it from the index with `git rm --cached <path>` and keep the working copy on disk.
- Keep commits focused on publishable skill changes, scripts, and repository documentation that is meant to ship.

## Planning Workflow

- Use `docs/plans/` for local design and implementation planning only.
- Use `docs/issues/` for local debugging notes, review findings, and temporary maintenance records.
- Treat both directories as workspace support material, not repository artifacts.

## OpenClaw Verification Notes

- When validating a skill through OpenClaw, verify the managed copy under `~/.openclaw/workspace/skills/<skill-slug>/` or `~/.openclaw/skills/<skill-slug>/` before assuming the repository draft is what the agent will execute.
- For main-agent reproduction, prefer `openclaw agent --agent main --json --message "..."` so the result is machine-readable and easier to compare across runs.
- For browser-session skills, validate against concrete protected targets and record whether the result is `ready`, `needs-user`, `challenge`, or `login-wall` instead of summarizing loosely as "worked" or "failed".
- After a verification run, inspect the corresponding OpenClaw session log under `~/.openclaw/agents/main/sessions/*.jsonl` to confirm which skill file was read, which script was invoked, and what raw tool result was returned.
- If the OpenClaw-managed skill and the repository draft differ, document that gap explicitly in `docs/issues/` so later implementation work does not confuse draft behavior with shipped behavior.
- Keep OpenClaw investigation notes, ad hoc verification outputs, and host-specific findings in `docs/issues/` as local-only support material; do not stage or publish them directly.

## Release Boundary

Before push or publish:

- verify that `docs/plans/` and `docs/issues/` are absent from staged changes
- verify that new root-level skills are complete and publishable
- verify that local secrets, runtime state, and host-specific notes remain untracked

## Version and Sync

This repository is the single source of truth for skill content. ClawHub is the versioned distribution channel.

- Track the current version in each published skill's SKILL.md frontmatter under `metadata.version`.
- Bump `metadata.version` before running `clawhub sync` or `clawhub publish`.
- The change flow is one-directional: repository → ClawHub registry → `~/.openclaw/skills/` managed copy.
- Do not publish directly from `~/.openclaw/skills/`; always publish from the repository.
- If OpenClaw runtime modifies scripts in the managed copy during use, port those changes back to the repository and bump the version before the next publish.
- After publishing, run `clawhub update` to align the managed copy with the registry.
