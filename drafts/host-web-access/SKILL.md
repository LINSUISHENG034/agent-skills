---
name: host-web-access
description: Use when a request needs public web search, page fetch, or Ubuntu-host browser access with durable site login reuse, bounded LAN noVNC recovery, or real page interaction on the agent host.
metadata:
  version: 0.1.0-draft
---

# Host Web Access

Use this draft when the agent needs public research plus the ability to escalate into the Ubuntu host browser for durable session reuse, bounded assisted recovery, or interactive operations that fetch-only tools cannot cover.

## Overview

`open-host-page.sh` is the canonical normal entrypoint. It:

- routes the request via `route-web-task.sh` so lightweight search/fetch take the default path for public content
- honors `--task-mode` and `--expected-action` to document caller intent and assert the normalized route before browser orchestration starts
- resolves the durable profile via `profile-resolution.sh` before browser start
- starts the host browser runtime only when the router returns `route: "browser"`
- uses local `host-page-ops.py` and `host-page-snapshot.py` helpers instead of importing `ubuntu-browser-session`
- always runs `cleanup-host-runtime.sh` so browser, Xvfb, x11vnc, and websockify PIDs are released after every task
- emits machine-readable JSON: all paths include `route`, `reason`, `needs_browser`, and `origin`; browser paths add `run_dir`, `profile_dir`, and `runtime_status`; assisted recovery additionally includes `assisted_session` and `lan_novnc_url`

Assisted flow is the exception path. The normal path is to complete work through `open-host-page.sh` without operator takeover.

## Routing Philosophy

Start with `WebSearch`, `WebFetch`, `curl`, or `Jina` for public requests. Escalate to the host browser only when `route-web-task.sh` emits `route: "browser"` with reasons such as `protected-site`, `dynamic-rendering`, `interaction-required`, `login-required`, or `host-browser-requested`. The JSON result includes `needs_browser` so downstream steps can log why the heavier runtime was required.

## Route Contract

- `task-mode` expresses caller intent such as `latest`, `article`, `interactive`, or `host-browser`
- `route` is the normalized router decision: `search`, `fetch`, or `browser`
- `reason` keeps the specific classification that explains why the route was chosen
- `--expected-action` asserts the normalized route returned by the router; it does not assert that browser startup or assisted recovery succeeded
- Route assertion failures happen before browser orchestration starts, so a mismatch never launches the runtime

## Assisted LAN Flow

The assisted path exposes a single fixed LAN `lan_novnc_url` on port `6084` by default. The `capture` command writes both the session manifest and site-session registry entry so future tasks reuse the same host profile.

## Identity And Protected Route Rules

Protected-site browser work stays in the host-browser workflow by default. The normal workflow does not hand protected tasks to a fetch-only path once browser routing is required.

Successor policy: one primary identity per canonical site. Secondary identities are opt-in and must be selected explicitly with `--session-key`; the skill does not auto-select between multiple identities.

This section defines the required public contract for successor behavior. Runtime enforcement coverage is being completed incrementally; when enforcement and policy diverge, follow this policy in operator and caller workflows.

## Cleanup Guarantees

Cleanup scripts stop browser, Xvfb, x11vnc, and websockify PIDs when present, remove temporary runtime directories, and rewrite the runtime state to `STATE=closed` while leaving persistent profile data untouched.

## Page Helper Usage

- Inspect current page state: `host-page-ops.py --check page-info`
- Navigate and wait for load completion: `host-page-ops.py --navigate "https://example.com" --wait-navigation`
- Click a visible link by text: `host-page-ops.py --click-link-text "Pricing"`
- Capture a markdown snapshot: `host-page-snapshot.py --format markdown`
- For dynamic pages, `host-page-ops.py` also supports `--retry N --retry-delay-ms MS` on `--eval` and `--check` flows
- Pass all flags in the same shell command invocation, and quote URLs, selectors, and JS expressions so the shell does not split them incorrectly

## Use Cases

- **Public research**: compare docs or fetch latest release notes with lightweight search/fetch; no browser ever starts because the router stays in `search` or `fetch`.
- **Protected site reuse**: open GitHub or Google via the maintained host profile, use `--session-key` to target a specific identity, and rely on the assisted path only when recovery requires operator help.
- **Interactive tasks**: need clicking, uploads, or dynamic rendering; escalate to the host browser, use `host-page-ops.py` for DOM work, capture snapshots with `host-page-snapshot.py`, and fall back to the assisted flow if challenges appear.
