# Result-Page Enhancements

## Topic-Links Heuristics

The `host-page-snapshot.py --format topic-links` extractor now applies generic result-page heuristics instead of returning every anchor on the page:

- Prefer repeated sibling containers when two or more candidate result blocks exist.
- Use `main`, `article`, and `[role=main]` roots as fallback scopes for extraction.
- Score multiple anchors per container and keep the best candidate link.
- Deduplicate by canonical absolute `href`.
- Attach a short optional `meta` snippet (`container.innerText`, max 400 chars).

## Scope Boundary

- Includes only generic result/topic detection logic.
- Excludes site-specific parsing rules and downstream content extraction.
