# Testing Matrix

- Runtime common helpers normalize origins, aliases, ports, and display selection
- Session manifest selection stays deterministic and never guesses among multiple sessions
- Site session registry survives broken JSON and still resolves the default session
- Profile resolution prefers site registry, then manifest, then identity/legacy/scoped fallbacks
- Browser runtime reports `missing` before first start, `stopped` for stale metadata, `running` for live Chrome, and `closed` after cleanup
- Browser runtime start requires a real browser command line and persists `cdp_host: 127.0.0.1`
- Assisted LAN start records `x11vnc.pid` and `websockify.pid`, status reports only the LAN noVNC URL, and stop clears assisted runtime state
- Host page helpers are local to `host-web-access` and do not import `ubuntu-browser-session`
- Cleanup is idempotent and safe when no browser resources are active
