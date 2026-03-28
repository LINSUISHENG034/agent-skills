# Third-Party Skill References

This directory is reserved for local-only third-party skill sources used as reference material while authoring skills in this repository.

Structure:

- `repos/`
  - Upstream repositories cloned locally so their history can be fetched and compared over time. This can be a full checkout or a sparse-checkout when you only need one subdirectory but still want repo-level tracking.
- `imports/`
  - Single copied skills or partial references kept locally when there is no repository-level upstream checkout.

Recommended layout:

```text
third_party/
  repos/
    baoyu-skills/
  imports/
    JimLiu/
      some-single-skill/
    unknown/
      copied-skill/
```

Rules:

- Keep all contents under `third_party/` out of version control unless there is a specific redistribution reason and it has been reviewed separately.
- Use the repository name directly under `repos/` and preserve upstream attribution inside local notes when needed.
- If you only need one folder from an upstream repository but still want `fetch` and `pull` support, keep it under `repos/` and use git sparse-checkout instead of copying the folder into `imports/`.
- For `imports/`, preserve upstream attribution in folder names when known.
- For copied material, keep a short local note with the source URL, author, capture date, and license status.
- Prefer `repos/` for long-term tracking and use `imports/` only for partial references that do not justify a full clone.

Sparse-checkout example:

```bash
git clone --filter=blob:none --sparse https://github.com/geekjourneyx/md2wechat-skill.git third_party/repos/md2wechat-skill
git -C third_party/repos/md2wechat-skill sparse-checkout set skills/md2wechat
```

This keeps `third_party/repos/md2wechat-skill/` as a normal git repository, so the updater script still works, while the working tree mainly exposes `skills/md2wechat/`.

Updater:

```bash
# Safe default: refresh remote tracking state only
bash scripts/update-third-party-repos.sh

# Explicit sync: fast-forward local checkouts after fetch
bash scripts/update-third-party-repos.sh --pull
```
