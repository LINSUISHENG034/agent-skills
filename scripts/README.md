# Scripts

Utility scripts for maintaining this skills repository and local OpenClaw skill
copies. Run commands from the repository root unless noted otherwise.

## Sync Skills to OpenClaw

Use `sync-skill-to-openclaw.sh` to copy one or more skills from this repository
into the local OpenClaw skills directory.

```bash
./scripts/sync-skill-to-openclaw.sh --skill host-web-access --from root
```

By default, the destination is `~/.openclaw/skills`, so the command above syncs
to `~/.openclaw/skills/host-web-access/`.

Common examples:

```bash
# Sync a published root-level skill.
./scripts/sync-skill-to-openclaw.sh --skill host-web-access --from root

# Let the script auto-detect root, drafts, or restricted.
./scripts/sync-skill-to-openclaw.sh --skill host-web-access

# Sync multiple restricted skills.
./scripts/sync-skill-to-openclaw.sh --from restricted --skill docx --skill xlsx

# Sync a draft skill.
./scripts/sync-skill-to-openclaw.sh --from drafts --skill my-draft-skill

# Keep destination-only files instead of deleting them.
./scripts/sync-skill-to-openclaw.sh --skill host-web-access --from root --no-delete

# Sync from an explicit absolute source root.
./scripts/sync-skill-to-openclaw.sh --source-root /abs/path/to/skills --skill some-skill
```

Options:

- `--skill <name>`: skill directory name to sync. Repeat for multiple skills.
- `--from auto|root|drafts|restricted`: source area to resolve from. Default is
  `auto`.
- `--source-root <abs-path>`: resolve skills from an explicit absolute source
  root instead of this repository.
- `--no-delete`: preserve files that exist only in the destination.

Environment variables:

- `SKILLS_REPO_ROOT`: repository root used by `--from`. Defaults to this repo.
- `OPENCLAW_SKILLS_DIR`: target directory. Defaults to `~/.openclaw/skills`.

The script excludes `.git/`, `.venv/`, `.pytest_cache/`, `__pycache__/`, and
`*.pyc`. Without `--no-delete`, it removes stale destination files.

## Update Third-Party Repositories

Use `update-third-party-repos.sh` to fetch all git repositories under
`third_party/repos`.

```bash
./scripts/update-third-party-repos.sh
```

Common examples:

```bash
# Fetch all remotes, prune deleted refs, and fetch tags.
./scripts/update-third-party-repos.sh

# Fetch, then fast-forward each repo when an upstream is configured.
./scripts/update-third-party-repos.sh --pull

# Use a custom third-party repository directory.
THIRD_PARTY_REPOS_DIR=/abs/path/to/repos ./scripts/update-third-party-repos.sh
```

Options:

- `--pull`: after fetching, run `git pull --ff-only` for repos with an upstream.

Environment variables:

- `THIRD_PARTY_REPOS_DIR`: repository directory to scan. Defaults to
  `third_party/repos`.

## Tests

Run the script test suites directly:

```bash
bash scripts/test_sync_skill_to_openclaw.sh
bash scripts/test_update_third_party_repos.sh
```
