---
name: host-web-access
description: Use when a request needs public web search, page fetch, or Ubuntu-host browser access with durable site login reuse, bounded LAN noVNC recovery, or real page interaction on the agent host.
metadata:
  version: 0.1.0-draft
---

# Host Web Access

Use this draft when the agent needs public research plus the ability to escalate into the Ubuntu host browser for durable session reuse, bounded assisted recovery, or interactive operations that fetch-only tools cannot cover.

## Overview

`open-host-page.sh` is the canonical entry point. It:

- routes the request via `route-web-task.sh` so lightweight search/fetch take the default path for public content
- honors `--task-mode` and `--expected-action` to document the intent and verify the router matches expectations
- resolves the durable profile via `profile-resolution.sh` before browser start
- starts the host browser runtime only when the router returns `route: "browser"`
- uses local `host-page-ops.py` and `host-page-snapshot.py` helpers instead of importing `ubuntu-browser-session`
- always runs `cleanup-host-runtime.sh` so browser, Xvfb, x11vnc, and websockify PIDs are released after every task

## Routing Philosophy

Start with `WebSearch`, `WebFetch`, `curl`, or `Jina` for public requests. Escalate to the host browser only when `route-web-task.sh` emits `route: "browser"` with reasons such as `protected-site`, `dynamic-rendering`, `interaction-required`, `login-required`, or `host-browser-requested`. The JSON result includes `needs_browser` so downstream steps can log why the heavier runtime was required.

## Assisted LAN Flow

The assisted path exposes a single fixed LAN `lan_novnc_url` on port `6084` by default. Normal recovery never emits loopback or SSH-forwarded URLs. The `capture` command writes both the session manifest and site-session registry entry so future tasks reuse the same host profile.

## Cleanup Guarantees

Cleanup scripts stop browser, Xvfb, x11vnc, and websockify PIDs when present, remove temporary runtime directories, and rewrite the runtime state to `STATE=closed` while leaving persistent profile data untouched.

## Use Cases

- **Public research**: compare docs or fetch latest release notes with lightweight search/fetch; no browser ever starts because the router stays in `search` or `fetch`.
- **Protected site reuse**: open GitHub or Google via the maintained host profile, use `--session-key` to target a specific identity, and rely on the assisted path only when recovery requires operator help.
- **Interactive tasks**: need clicking, uploads, or dynamic rendering; escalate to the host browser, use `host-page-ops.py` for DOM work, capture snapshots with `host-page-snapshot.py`, and fall back to the assisted flow if challenges appear.
