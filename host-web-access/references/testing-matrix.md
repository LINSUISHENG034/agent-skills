# Testing Matrix

- Runtime common helpers normalize origins, aliases, ports, and display selection
- Validate identity governance: one primary identity per canonical site and explicit `session-key` requirement for secondary identities
- Session manifest selection stays deterministic and never guesses among multiple sessions
- Site session registry survives broken JSON and still resolves the default session
- Profile resolution prefers site registry, then manifest, then identity/legacy/scoped fallbacks
- Browser runtime reports `missing` before first start, `stopped` for stale metadata, `running` for live Chrome, and `closed` after cleanup
- Browser runtime start requires a real browser command line and persists `cdp_host: 127.0.0.1`
- Browser runtime restores runtime reuse primitives: `select-target` ranks page targets from `/json/list` and returns no usable target for off-origin-only lists, `check-page` supports `challenge|login-wall|page-info`, and `verify` marks manifests stale cleanly for dead-browser, unreachable-CDP, and missing-target branches
- Browser runtime clears stale Chromium singleton locks before launch while preserving live locks, and auto-selects free CDP/display values when callers leave them unspecified
- Verify wrong-page recovery before user takeover so assisted sessions begin from the expected account page
- Validate LAN-only assisted handoff through the public JSON contract: `open-host-page.sh` always emits `status`, `next_action`, and `operator_required`; blocked handoff also emits `operator_url`, `blocking_reason`, `resume_command`, and `message_for_agent`
- Validate assisted-session JSON output: `start|status` emit the explicit noVNC handoff contract, `capture` emits `capture_completed: true`, and `stop` emits `assisted_session_stopped: true`
- Confirm browser-route continuity on protected tasks from initial route classification through post-recovery continuation
- Assisted LAN start records `x11vnc.pid` and `websockify.pid`, status preserves the explicit JSON handoff contract, and stop clears assisted runtime state
- Host page helpers are local to `host-web-access`, do not import `ubuntu-browser-session`, and expose retry/help coverage for dynamic-page checks plus shell-safe invocation guidance
- Cleanup is idempotent and safe when no browser resources are active
