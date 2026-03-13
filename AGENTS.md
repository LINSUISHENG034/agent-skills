# Repository Working Rules

This repository is for publishable skills plus local-only development support files.

## Skill Development Scope

- Build new or incomplete skills under `drafts/`.
- Promote a skill to the repository root only when it is ready to publish.
- Keep published root-level skills portable and redistributable.
- Reuse existing scripts and references where practical instead of duplicating workflows across skills.

## Skill Authoring Principles

- Start from 2-3 concrete use cases before writing the skill structure or scripts.
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

## Release Boundary

Before push or publish:

- verify that `docs/plans/` and `docs/issues/` are absent from staged changes
- verify that new root-level skills are complete and publishable
- verify that local secrets, runtime state, and host-specific notes remain untracked
