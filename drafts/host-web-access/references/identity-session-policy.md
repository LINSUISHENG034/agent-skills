# Identity Session Policy

## Public Rules

- one primary identity per canonical site
- No automatic guessing between multiple identities
- non-default identities require an explicit session-key

## Successor Scope

This document codifies the successor-facing policy contract. The current runtime is converging to this contract and may not yet enforce every rule in all paths.

Policy target: the default session for a protected site is the declared primary identity in registry or manifest data. When more than one identity exists for the same canonical site, callers must provide `--session-key` for any non-default identity.

If identity state and live browser page drift, recover to the expected account page before any user takeover. The assisted path remains LAN-scoped through `lan_novnc_url`.

Assisted capture writes reusable metadata only after runtime verification confirms:
- no active challenge
- no login wall
- final page URL still matches the requested target URL when provided (otherwise same-origin requirement still applies)

On successful assisted capture, manifest state is written at `--manifest-root`, while reusable identity/session metadata is written under the main skill root (`$HOME/.agent-browser/index/`), not under the override manifest root.

`open-host-page.sh` does not auto-capture blocked assisted states. It returns the LAN handoff payload first so the operator can complete the required interaction before capture is attempted.
