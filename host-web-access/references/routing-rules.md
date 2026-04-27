# Routing Rules

- `task-mode` is caller intent; it is not the final action that will run
- `route-web-task.sh` normalizes intent into `route: "search"`, `route: "extract"`, or `route: "browser"`
- `reason` preserves the more specific classification behind that normalized route, such as `latest-info`, `public-article`, or `interaction-required`
- `open-host-page.sh --expected-action` asserts the normalized route before any browser orchestration starts
- `open-host-page.sh` always returns machine-readable JSON with `route`, `reason`, `needs_browser`, `origin`, `status`, `next_action`, and `operator_required`; browser routes also report `runtime_status`, `page_status`, `recovery_attempted`, and (when resolved) `target_id`
- `extract` routes skip profile resolution and browser startup; single results expose `content_contract: "markdown-snapshot"` and batch results expose `content_contract: "batch-markdown-snapshot"`
- Extract results include `extraction_method`, `quality`, `summary`, optional `saved_path`, and explicit `needs_browser_reason` when browser escalation is recommended
- Browser-route success means target-page correctness, not only runtime startup: `page_status` is one of `ready`, `challenge`, `login-wall`, or `target-mismatch`
- Browser routing reuses existing runtime sessions only after hard `verify` checks pass; stale `status: running` metadata is not enough
- Wrong-page drift gets one local recovery attempt before assisted escalation; assisted handoff is reserved for explicit blocked states (`challenge`, `login-wall`) or unrecovered `target-mismatch`
- `browser-runtime.sh doctor` returns JSON health diagnostics and can repair stale state with `--repair`
- Assisted recovery includes `operator_url`, `blocking_reason`, `resume_command`, `message_for_agent`, `assisted_session`, and `lan_novnc_url`; `open-host-page.sh` returns this handoff payload and does not auto-run assisted `capture`/`stop` for blocked states
- Page operations use the local `host-cdp-core.py` module only; there are no runtime imports from `ubuntu-browser-session`
- Host page helpers default to CDP port `9222` unless the runtime provides an explicit override
- Runtime-owned browser sessions bind CDP to `127.0.0.1`; LAN exposure is limited to the fixed noVNC operator URL
