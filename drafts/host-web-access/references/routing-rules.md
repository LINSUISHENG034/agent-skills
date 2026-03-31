# Routing Rules

- Start with lightweight tools for public content; escalate to the Ubuntu host browser only when `scripts/route-web-task.sh` reports a `browser` route such as `protected-site`, `dynamic-rendering`, `interaction-required`, `login-required`, or `host-browser-requested`. The router’s JSON includes `needs_browser` so downstream steps can log why the heavier runtime launched.
- After escalation, use `host-page-ops.py` for DOM actions, capture rendered content via `host-page-snapshot.py`, and only trigger assisted recovery once the runtime is still not running.
