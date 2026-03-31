# Cleanup Model

- Cleanup must be safe to call on an empty runtime directory
- Browser, Xvfb, x11vnc, and websockify PID files are stopped and removed when present
- Runtime state is rewritten to `closed` after cleanup and clears the persisted browser PID
- Runtime metadata keeps the last known browser command, CDP host/port, display, origin, profile, and session key
- Persistent profile data remains outside the runtime directory
