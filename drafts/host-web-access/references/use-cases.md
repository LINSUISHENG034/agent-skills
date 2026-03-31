# Use Cases

- Public web lookup without browser startup
- Protected site reuse with host-side persistent profile
- Explicit non-default `session-key` profile selection
- Validate the integrated `open-host-page.sh` path: the router stays on lightweight search when `route: "search"`, launches the browser runtime only when the router reports `browser`, triggers the assisted LAN flow only when recovery fails, and always runs cleanup
- Confirm fixed-port LAN assisted recovery by starting a blocked session and verifying `assist-lan-session.sh` prints the single `lan_novnc_url` and updates the manifest/site registry
