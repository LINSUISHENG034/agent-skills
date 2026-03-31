# Identity Session Policy

## Public Rules

- one primary identity per canonical site
- No automatic guessing between multiple identities
- non-default identities require an explicit session-key

## Successor Scope

This document codifies the successor-facing policy contract. The current runtime is converging to this contract and may not yet enforce every rule in all paths.

Policy target: the default session for a protected site is the declared primary identity in registry or manifest data. When more than one identity exists for the same canonical site, callers must provide `--session-key` for any non-default identity.

If identity state and live browser page drift, recover to the expected account page before any user takeover. The assisted path remains LAN-scoped through `lan_novnc_url`.
