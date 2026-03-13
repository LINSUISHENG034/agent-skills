---
name: agent-browser-ubuntu-server
description: Use when a request needs a real Ubuntu Server browser session for protected-site browsing, session reuse, challenge recovery, or host-side page inspection with minimal repeated user assistance.
---

# Agent Browser Ubuntu Server

Standalone browser workflow for Ubuntu Server hosts that keeps session recovery centered on a durable `session manifest`, not just exported cookies.

## When To Use

- Open, inspect, or interact with a site from a headless Ubuntu Server host
- Reuse a previously verified browser session instead of creating a fresh browser instance
- Recover a challenge-blocked or degraded protected-site session with the least user help
- Distinguish Cloudflare or Turnstile challenge pages from login walls before escalating

Representative requests:

- "Open this site on the server and tell me what the page shows."
- "Continue browsing that dashboard from yesterday's session."
- "This page is back on Verify you are human. Recover it if possible."
- "Reuse the same browser session from the Ubuntu host."

## Do Not Use

- General web research that can be answered with HTTP fetches or web search
- Local desktop GUI browsing outside the Ubuntu Server environment
- Tasks where API keys, service tokens, or a non-browser auth flow are sufficient
- Pure bootstrap-only login help when no follow-on browser workflow is needed

## Environment Requirements

Check for the host-side dependencies first:

```bash
command -v python3
command -v curl
command -v jq
command -v Xvfb
command -v x11vnc
command -v websockify
command -v google-chrome || command -v chromium || command -v chromium-browser
```

Runtime assumptions:

- Ubuntu Server or equivalent Linux host
- Python 3 standard library only for CDP WebSocket evaluation
- Chrome or Chromium exposed through `--remote-debugging-port`
- `Xvfb` available for GUI-mode challenge handling without a physical display

## Workflow

Always work in this order:

1. Discover a matching manifest for the target origin
2. Validate the manifest and the recorded browser process
3. Attach to the existing browser session when it is still live
4. Use headless direct browse for unknown or low-risk public pages
5. Escalate to GUI-mode auto-browse when headless mode is blocked by a challenge
6. Ask the user for help only after local recovery paths are exhausted

Preferred autonomous entrypoint:

```bash
{baseDir}/scripts/open-protected-page.sh --url 'https://target.example' --session-key default
```

Use the lower-level scripts below when you need to inspect or repair an individual stage manually.

### 1. Discover Existing Session State

Use the manifest helper first, or let the wrapper do it for you:

```bash
{baseDir}/scripts/open-protected-page.sh --url 'https://target.example' --session-key default
{baseDir}/scripts/session-manifest.sh list
{baseDir}/scripts/session-manifest.sh select --origin 'https://target.example' --account-hint 'acct-a'
```

The selector must fail on ambiguous same-origin sessions instead of choosing arbitrarily.

### 2. Validate Or Recover The Session

Validate the current browser process and CDP target:

```bash
{baseDir}/scripts/browser-runtime.sh verify --origin 'https://target.example' --session-key default
```

If the browser process is gone but the profile directory is still usable, restart the runtime with the same profile:

```bash
{baseDir}/scripts/browser-runtime.sh start --url 'https://target.example' --mode gui --profile-dir ~/.agent-browser/profiles/target.example
```

### 3. Attach Existing Session

When validation succeeds, keep using the recorded browser context:

```bash
{baseDir}/scripts/browser-runtime.sh attach --origin 'https://target.example' --session-key default
{baseDir}/scripts/browser-runtime.sh list-targets --origin 'https://target.example' --session-key default
```

### 4. Direct Browse First

For public or low-risk pages, try headless mode before escalating:

```bash
{baseDir}/scripts/browser-runtime.sh start --url 'https://target.example' --mode headless
{baseDir}/scripts/browser-runtime.sh status
```

### 5. Detect The Blockage Type

Use CDP page checks to decide whether the page is blocked by an anti-bot challenge or a login wall:

```bash
TARGETS_JSON="$({baseDir}/scripts/browser-runtime.sh list-targets --origin 'https://target.example' --session-key default)"
TARGET_ID="$({baseDir}/scripts/browser-runtime.sh select-target --origin 'https://target.example' --targets-json "$TARGETS_JSON")"
{baseDir}/scripts/browser-runtime.sh check-page --origin 'https://target.example' --session-key default --target-id "$TARGET_ID" --check challenge
{baseDir}/scripts/browser-runtime.sh check-page --origin 'https://target.example' --session-key default --target-id "$TARGET_ID" --check login-wall
{baseDir}/scripts/browser-runtime.sh check-page --origin 'https://target.example' --session-key default --target-id "$TARGET_ID" --check page-info
```

Challenge indicators:

- Titles such as `请稍候`, `Just a moment`, `Checking your browser`, `Verify you are human`
- HTML or body hits such as `cf-challenge`, `challenge-platform`, `turnstile`, `captcha`

Login-wall indicators:

- Body text such as `Sign in`, `Log in`, `登录`, `Create your account`, `Sign up`
- URL patterns such as `/login`, `/signin`, `/auth`, `/i/flow/login`

Real-site examples:

- Cloudflare JS challenge path: `linux.do`
- Login wall path: `x.com`

### 6. Use GUI Auto-Browse Before Asking The User

When headless mode is challenge-blocked but not login-walled, move to GUI mode on `Xvfb` and re-check the same page:

```bash
{baseDir}/scripts/browser-runtime.sh start --url 'https://target.example' --mode gui --profile-dir ~/.agent-browser/profiles/target.example
{baseDir}/scripts/browser-runtime.sh status
```

If GUI mode still leaves the page blocked or the site needs credentials, start the assisted overlay:

```bash
{baseDir}/scripts/assisted-session.sh start --url 'https://target.example' --origin 'https://target.example' --session-key default
{baseDir}/scripts/assisted-session.sh status --origin 'https://target.example' --session-key default
```

After the user finishes the blocked step and the host-side verification is clean, capture the manifest for later reuse:

```bash
{baseDir}/scripts/assisted-session.sh capture --origin 'https://target.example' --session-key default
```

## Failure And Recovery Rules

- If multiple same-origin sessions exist, require `--account-hint` or `--task-scope`
- If the manifest process is dead, mark the manifest stale and try profile restart before asking the user
- If challenge checks still return blocked after GUI mode, ask the user to use the noVNC session
- If login-wall checks remain true, ask the user to authenticate in the live browser and leave the final page loaded
- If no reusable session exists, create a new assisted session only once per recovery attempt

## Key Files

- `scripts/session-manifest.sh`: manifest CRUD, indexing, and safe selection
- `scripts/open-protected-page.sh`: high-level protected-page orchestration for OpenClaw
- `scripts/cdp-eval.py`: standard-library CDP WebSocket evaluation helper
- `scripts/browser-runtime.sh`: headless and GUI runtime management
- `scripts/assisted-session.sh`: noVNC-assisted flow layered on the same live browser session

See also:

- `references/use-cases.md`
- `references/session-manifest.md`
- `references/assisted-session-flow.md`
- `references/testing-matrix.md`
