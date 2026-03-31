# Assisted LAN Flow

- Assisted recovery assumes the browser runtime is already running in GUI mode and exposes a valid X display
- `assist-lan-session.sh start` attaches `x11vnc` to that display and serves noVNC through `websockify`
- The operator URL is LAN-only and fixed to port `6084` by default; constrained/container environments should set `AGENT_BROWSER_NOVNC_PUBLIC_HOST` explicitly to a LAN-reachable host or IP
- `status` returns only `lan_novnc_url` so downstream tooling does not advertise local-only access paths
- `capture` inspects the live runtime target (`list-targets` + `select-target` + `check-page`) and refuses to persist reusable state while challenge/login-wall/off-origin drift is still present
- successful `capture` writes:
  - session manifest at `--manifest-root`
  - site session registry at the main skill root (`$HOME/.agent-browser/index/site-sessions.json`)
  - identity providers at the main skill root (`$HOME/.agent-browser/index/identity-profiles.json`)
