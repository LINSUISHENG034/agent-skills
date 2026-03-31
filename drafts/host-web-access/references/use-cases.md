# Use Cases

- Public web lookup without browser startup
- Protected site reuse with host-side persistent profile
- Explicit non-default `session-key` profile selection
- Validate the routing contract: `task-mode` expresses caller intent, `route` normalizes that intent to `search`, `fetch`, or `browser`, and `reason` preserves the specific classification that justified the route
- Verify `--expected-action` as a route assertion only: mismatches fail before browser orchestration starts, while successful `browser` routing can still surface runtime or assisted-recovery status separately
- Validate the integrated `open-host-page.sh` path: the router stays on lightweight search when `route: "search"`, launches the browser runtime only when the router reports `browser`, triggers the assisted LAN flow only when recovery fails, and always runs cleanup
- Confirm fixed-port LAN assisted recovery by starting a blocked session and verifying `assist-lan-session.sh` prints the single `lan_novnc_url` and updates the manifest/site registry
- Capture page state quickly with `host-page-ops.py --check page-info` before deciding whether to click, scroll, or snapshot
- Navigate with `host-page-ops.py --navigate "https://example.com" --wait-navigation` when the caller needs the next page to finish loading before further DOM operations
- Use `host-page-ops.py --click-link-text "Pricing"` for generic visible-link navigation instead of site-specific selectors when text matching is sufficient
- Export page content with `host-page-snapshot.py --format markdown` for downstream summarization or operator review
- For shell safety, keep flags in the same command invocation and quote URLs, selectors, and JS expressions; splitting `--wait-navigation` onto its own shell line creates a separate shell command rather than an extra flag
