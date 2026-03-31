# Assisted LAN Flow

- Assisted sessions expose only a fixed LAN URL (`lan_novnc_url`) on port 6084. The `status` command never prints loopback or SSH-forwarded URLs, so Windows clients only need the LAN address and a firewall exception kept open once.
- `start` captures the origin/session/profile context, writes the LAN URL to state, and returns `lan_novnc_url` to the caller.
- `status` only reports the stored LAN URL and verifies the assisted session is still associated with the tracked runtime.
- `capture` writes both the session manifest and the site session registry entry, ensuring the same durable profile is reused once the user finishes the assisted flow.
- `stop` removes the runtime state file without touching persistent profile data.
