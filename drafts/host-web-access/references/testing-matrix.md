# Testing Matrix

- Runtime common helpers normalize origins, aliases, ports, and display selection
- Validate identity governance: one primary identity per canonical site and explicit `session-key` requirement for secondary identities
- Session manifest selection stays deterministic and never guesses among multiple sessions
- Site session registry survives broken JSON and still resolves the default session
- Profile resolution prefers site registry, then manifest, then identity/legacy/scoped fallbacks
- Browser runtime reports `missing` before first start, `stopped` for stale metadata, `running` for live Chrome, and `closed` after cleanup
- Browser runtime start requires a real browser command line and persists `cdp_host: 127.0.0.1`
- Verify wrong-page recovery before user takeover so assisted sessions begin from the expected account page
- Validate LAN-only assisted handoff by asserting only `lan_novnc_url` is exposed in operator-facing recovery output
- Confirm browser-route continuity on protected tasks from initial route classification through post-recovery continuation
- Assisted LAN start records `x11vnc.pid` and `websockify.pid`, status reports only the LAN noVNC URL, and stop clears assisted runtime state
- Host page helpers are local to `host-web-access`, do not import `ubuntu-browser-session`, and expose retry/help coverage for dynamic-page checks plus shell-safe invocation guidance
- Cleanup is idempotent and safe when no browser resources are active
