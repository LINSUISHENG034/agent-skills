# Assisted LAN Flow

- Assisted recovery assumes the browser runtime is already running in GUI mode and exposes a valid X display
- `assist-lan-session.sh start` attaches `x11vnc` to that display and serves noVNC through `websockify`
- The operator URL is LAN-only and fixed to port `6084` by default; loopback fallback is rejected
- `status` returns only `lan_novnc_url` so downstream tooling does not advertise local-only access paths
- `capture` writes the session manifest and site-session registry while preserving the existing browser profile
