# Routing Rules

- `task-mode` is caller intent; it is not the final action that will run
- `route-web-task.sh` normalizes intent into `route: "search"`, `route: "fetch"`, or `route: "browser"`
- `reason` preserves the more specific classification behind that normalized route, such as `latest-info`, `public-article`, or `interaction-required`
- `open-host-page.sh --expected-action` asserts the normalized route before any browser orchestration starts
- `open-host-page.sh` always returns machine-readable JSON with `route`, `reason`, `needs_browser`, and `origin`; browser routes add runtime/profile context, and assisted recovery additionally includes `assisted_session` plus `lan_novnc_url`
- Page operations use the local `host-cdp-core.py` module only; there are no runtime imports from `ubuntu-browser-session`
- Host page helpers default to CDP port `9222` unless the runtime provides an explicit override
- Runtime-owned browser sessions bind CDP to `127.0.0.1`; LAN exposure is limited to the fixed noVNC operator URL
