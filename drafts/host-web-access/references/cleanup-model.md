# Cleanup Model

- Cleanup must be safe to call on an empty runtime directory
- Browser, Xvfb, x11vnc, and websockify PID files are stopped and removed when present
- Runtime state is rewritten to `closed` after cleanup
- Persistent profile data remains outside the runtime directory
- Runtime metadata captures `MODE`, `ORIGIN`, `SESSION_KEY`, `PROFILE_DIR`, and binds `cdp_host=127.0.0.1`.
- Run `cleanup-host-runtime.sh` after every success, failure, or assisted capture so the GUI/CDP helpers have a deterministic lifecycle.
