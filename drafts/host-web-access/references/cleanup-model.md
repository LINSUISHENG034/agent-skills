# Cleanup Model

- Cleanup must be safe to call on an empty runtime directory
- Browser, Xvfb, x11vnc, and websockify PID files are stopped and removed when present
- Runtime state is rewritten to `closed` after cleanup
- Persistent profile data remains outside the runtime directory
