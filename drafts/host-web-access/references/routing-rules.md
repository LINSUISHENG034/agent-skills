# Routing Rules

- Page operations use the local `host-cdp-core.py` module only; there are no runtime imports from `ubuntu-browser-session`
- Host page helpers default to CDP port `9222` unless the runtime provides an explicit override
- Runtime-owned browser sessions bind CDP to `127.0.0.1`; LAN exposure is limited to the fixed noVNC operator URL
