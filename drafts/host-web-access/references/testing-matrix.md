# Testing Matrix

- Runtime common helpers normalize origins, aliases, ports, and display selection
- Session manifest selection stays deterministic and never guesses among multiple sessions
- Site session registry survives broken JSON and still resolves the default session
- Profile resolution prefers site registry, then manifest, then identity/legacy/scoped fallbacks
- Browser runtime reports `stopped` before start, `running` after start, and `closed` after cleanup
- Cleanup is idempotent and safe when no browser resources are active and runtime metadata is rewritten to `STATE=closed`
- `test_browser_runtime.sh` must fail before `browser-runtime.sh` exists and pass once start/status/stop/list-targets/cleanup behave correctly
- `test_session_manifest.sh` must fail before `session-manifest.sh` is wired up and pass once manifests write/list/select correctly.
- `test_site_session_registry.sh` and `test_profile_resolution.sh` should pass to confirm canonical site profiles and legacy fallbacks stay accessible.
- `test_assist_lan_session.sh` must fail before `assist-lan-session.sh` exists and pass once the fixed-port assisted flow reports only `lan_novnc_url` while start/capture/stop update the manifest and release runtime state.
- `test_open_host_page.sh` must fail before `open-host-page.sh` exists and pass once the router, lightweight mode, browser runtime, assisted recovery, and cleanup happen in the documented order under `open-host-page.sh`.
- `test_route_web_task.sh` must fail before `route-web-task.sh` exists and pass once the router emits deterministic JSON reasons for search/fetch/browser escalation.
