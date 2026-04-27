---
name: host-web-access
description: Use when a request needs public web search, page fetch, or Ubuntu-host browser access with durable site login reuse, bounded LAN noVNC recovery, or real page interaction on the agent host.
metadata:
  version: 1.1.0
  status: active
---

# Host Web Access

Use this skill when the agent needs public research plus the ability to escalate into the Ubuntu host browser for durable session reuse, bounded assisted recovery, or interactive operations that fetch-only tools cannot cover.

## Overview

`open-host-page.sh` is the canonical normal entrypoint. It:

- routes the request via `route-web-task.sh` so lightweight search/fetch take the default path for public content
- uses a content-first `extract` route for article and batch-read tasks before any browser escalation
- honors `--task-mode` and `--expected-action` to document caller intent and assert the normalized route before browser orchestration starts
- resolves the durable profile via `profile-resolution.sh` before browser start
- starts the host browser runtime only when the router returns `route: "browser"`
- uses local `host-page-ops.py` and `host-page-snapshot.py` helpers instead of importing `ubuntu-browser-session`
- preserves the browser runtime for successful browser-route handoff so follow-up CDP, snapshot, and DOM helper calls can reuse the returned session
- accepts `--cleanup-on-exit` when the caller explicitly wants one-shot browser work that tears down the runtime before script exit
- preserves runtime and helper state when assisted handoff is returned; cleanup happens after assisted capture/stop or explicit cleanup
- emits machine-readable JSON: all paths include `route`, `reason`, `needs_browser`, `origin`, `status`, `next_action`, and `operator_required`; extract paths add the markdown snapshot contract fields; browser paths add `run_dir`, `profile_dir`, `runtime_status`, and `page_status`; assisted recovery additionally includes `operator_url`, `blocking_reason`, `resume_command`, `message_for_agent`, `assisted_session`, and `lan_novnc_url`

Assisted flow is the exception path. The normal path is to complete work through `open-host-page.sh` without operator takeover.

## Routing Philosophy

Start with `WebSearch`, `WebFetch`, `curl`, or `Jina` for latest/public discovery. Use `--task-mode article` or `--task-mode batch-read` for content-understanding tasks; those route to `extract` and call `content-extract.py` without starting a browser. Escalate to the host browser only when `route-web-task.sh` emits `route: "browser"` with reasons such as `protected-site`, `dynamic-rendering`, `interaction-required`, `login-required`, or `host-browser-requested`, or when extract output sets `needs_browser: true`.

## Route Contract

- `task-mode` expresses caller intent such as `latest`, `article`, `batch-read`, `interactive`, or `host-browser`
- `route` is the normalized router decision: `search`, `extract`, or `browser`
- `reason` keeps the specific classification that explains why the route was chosen
- `status` is the canonical task outcome for agents: `ready` when autonomous work may continue, `needs-user` when a human handoff is required
- `next_action` is the explicit next step for the caller: `none` for ready states, `open-novnc` for assisted handoff
- `operator_required` is the hard stop bit; when it is `true`, do not continue autonomous browsing
- `--expected-action` asserts the normalized route returned by the router; it accepts `search`, `fetch`, `extract`, `browser`, or legacy `lightweight`; it does not assert that browser startup or assisted recovery succeeded
- Route assertion failures happen before browser orchestration starts, so a mismatch never launches the runtime

## Content Extraction And Markdown Snapshots

Use `--task-mode article` for a single read-only URL and `--task-mode batch-read` with repeated `--url` flags for multi-link triage. Both modes use the `extract` route, skip profile resolution, skip browser startup, and return an agent-friendly content result.

For durable notes, pass `--output-dir DIR`. The extractor writes markdown snapshots with frontmatter:

```yaml
---
title: "..."
url: "..."
source_type: "web"
content_type: "article"
extraction_method: "http-html"
fetched_at: "..."
quality: "high"
---
```

Single extract results include `content_contract: "markdown-snapshot"`, `title`, `url`, `source_type`, `content_type`, `extraction_method`, `quality`, `summary`, optional `markdown`, optional `saved_path`, `needs_browser`, and `needs_browser_reason`. Batch results use `content_contract: "batch-markdown-snapshot"` plus `results[]` and `quality_summary`.

Escalation is explicit: if lightweight extraction fails or returns low-quality content, the payload sets `needs_browser: true` with `needs_browser_reason` such as `extraction-failed` or `low-quality-extraction`. The caller can then rerun with `--task-mode interactive`, `--task-mode dynamic`, or `--task-mode host-browser`.

## Assisted LAN Flow

The assisted path exposes a single fixed LAN `lan_novnc_url` on port `6084` by default. Assisted outputs also include `operator_url`, `resume_command`, and `message_for_agent` so the next step is explicit. The `capture` command writes both the session manifest and site-session registry entry so future tasks reuse the same host profile.

Common blocked-site pattern: when `operator_required: true` and `next_action: open-novnc`, the live browser has already hit a challenge such as Cloudflare Turnstile, reCAPTCHA, or a login wall. Show the user `operator_url` or `lan_novnc_url`, tell them to complete the challenge in that remote browser, then resume only through `resume_command`. Do not keep autonomous browsing after the handoff payload is returned.

## Identity And Protected Route Rules

Protected-site browser work stays in the host-browser workflow by default. The normal workflow does not hand protected tasks to a fetch-only path once browser routing is required.

Successor policy: one primary identity per canonical site. Secondary identities are opt-in and must be selected explicitly with `--session-key`; the skill does not auto-select between multiple identities.

This section defines the required public contract for successor behavior. Runtime enforcement coverage is being completed incrementally; when enforcement and policy diverge, follow this policy in operator and caller workflows.

Agent rule: if `operator_required` is `true`, stop autonomous browsing, show the user `operator_url`, and resume only through `resume_command` after the user completes the required interaction.

## Cleanup Guarantees

Cleanup scripts stop browser, Xvfb, x11vnc, and websockify PIDs when present, remove temporary runtime directories, and rewrite the runtime state to `STATE=closed` while leaving persistent profile data untouched. When assisted handoff is active, runtime state is intentionally preserved until assisted capture/stop finalizes the session.

`open-host-page.sh` preserves browser runtimes for successful browser-route `ready` results by default so downstream helpers can reuse the same CDP session. Reuse is gated by `browser-runtime.sh verify`, which checks the browser process, CDP `/json/version`, and the selected target when present. If verification fails, `open-host-page.sh` cleans up stale runtime state before starting a fresh browser instead of trusting weak `status: running` metadata.

Use `browser-runtime.sh doctor --run-dir DIR --origin URL --session-key KEY` to inspect runtime health. It returns JSON with `status`, `runtime_status`, `issues`, `repaired`, and `suggested_action`. Add `--repair` to clean stale runtime state and mark the manifest stale when possible.

## Page Helper Usage

- Inspect current page state: `host-page-ops.py --check page-info`
- Navigate and wait for load completion: `host-page-ops.py --navigate "https://example.com" --wait-navigation`
- Click a visible link by text: `host-page-ops.py --click-link-text "Pricing"`
- Capture a markdown snapshot: `host-page-snapshot.py --format markdown`
- For dynamic pages, `host-page-ops.py` also supports `--retry N --retry-delay-ms MS` on `--eval` and `--check` flows
- After `open-host-page.sh` returns a browser-route `ready` payload, reuse the returned `run_dir` and live runtime for helper calls; do not assume the session is ephemeral unless you passed `--cleanup-on-exit`
- Pass all flags in the same shell command invocation, and quote URLs, selectors, and JS expressions so the shell does not split them incorrectly

## GPU Crash On Headless Servers

GUI browser startup on GPU-less Ubuntu hosts can expose a Chrome startup that opens a CDP port but never renders the page correctly. A common symptom is Chrome logging `Exiting GPU process due to errors during initialization` while the task still appears superficially `ready`.

The GUI launch path now includes a safer server-host preset with `--disable-gpu` and `--enable-unsafe-swiftshader`. If rendering still looks suspect:

- verify the live page with `host-page-ops.py --check page-info` or `host-page-snapshot.py` before assuming the browser is usable
- prefer the assisted LAN flow when a human can recover the page more quickly than repeated autonomous retries
- run `browser-runtime.sh doctor --run-dir DIR --origin URL --session-key KEY`
- inspect browser logs under the returned runtime log directory and then retry or use the assisted LAN flow

`status: ready` means the runtime and selected target were available at handoff time; it does not guarantee that a protected or GPU-sensitive page is still rendering correctly after launch.

## Use Cases

- **Public research**: compare docs or fetch latest release notes with lightweight search/fetch; no browser ever starts because the router stays in `search` or `fetch`.
- **Article extraction**: read one URL with `open-host-page.sh --url "https://example.com/post" --task-mode article --expected-action extract --output-dir notes/`.
- **Batch triage**: read several URLs cheaply with repeated `--url` flags and `--task-mode batch-read`, then escalate only results whose payload sets `needs_browser: true`.
- **Protected site reuse**: open GitHub or Google via the maintained host profile, use `--session-key` to target a specific identity, and rely on the assisted path only when recovery requires operator help.
- **Interactive tasks**: need clicking, uploads, or dynamic rendering; escalate to the host browser, use `host-page-ops.py` for DOM work, capture snapshots with `host-page-snapshot.py`, and fall back to the assisted flow if challenges appear.
