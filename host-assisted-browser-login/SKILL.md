---
name: host-assisted-browser-login
description: Use when a headless Ubuntu or Linux host needs a real browser login session, cookies, OAuth state, CAPTCHA completion, or 2FA, and the user can help from another machine.
---

# Host-Assisted Browser Login

## Overview

Use this skill when the host needs a real logged-in browser, not hand-crafted cookies. Default to the bundled script and treat manual commands as fallback only.

This skill is a login-bootstrap companion for a browser-interaction skill such as an externally installed `agent-browser`: use this one to establish the host-side authenticated session, then hand routine page interaction back to that companion skill.

Primary commands:

```bash
scripts/browser-login-stack.sh start --url 'https://example.com'
scripts/browser-login-stack.sh status
scripts/browser-login-stack.sh stop
```

## When To Use

- Headless Ubuntu or Linux host with no GUI
- Interactive login, CAPTCHA, OAuth, passkeys, OTP, or 2FA
- Agent needs host-side cookies, local storage, or a reusable browser profile
- Headless browser mode is blocked or unreliable

If you also need general browser interaction after login, install a companion skill such as:

```bash
npx clawhub@latest install agent-browser
```

## Do Not Use

- API keys, service tokens, or device code flows are sufficient
- No browser session is required
- The site policy forbids this workflow

## Dependencies

Check:

```bash
command -v Xvfb
command -v x11vnc
command -v websockify
command -v google-chrome || command -v chromium || command -v chromium-browser
```

If missing, ask the user to install:

```bash
sudo apt-get update
sudo apt-get install -y xvfb x11vnc novnc websockify
```

## Standard Workflow

### 1. Start the stack

Run:

```bash
scripts/browser-login-stack.sh start --url 'https://target.example'
```

Use `status` to confirm noVNC and DevTools are reachable. If the script cannot start the stack or deeper debugging is needed, read `references/manual-fallback.md`.

### 2. Guide the user

Give the user the noVNC URL reported by `status` or `start`.

For Windows users, if direct access times out or the host firewall blocks `6080`, prefer SSH port forwarding:

```powershell
ssh -L 6080:127.0.0.1:6080 -L 9222:127.0.0.1:9222 USER@HOST_IP
```

Then the user opens:

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote
```

Ask the user to log in inside the host browser, complete CAPTCHA or 2FA, leave the session open, and tell the agent when the target page is loaded.

### 3. Verify on the host

Do not trust the user's report alone. Re-check the host browser state through DevTools:

```bash
curl -s http://127.0.0.1:9222/json/list
```

Confirm:

- final URL is correct
- title and visible content match a logged-in state
- login prompts are gone

If a page looked missing before login, revisit the exact URL after authentication before concluding it is gone.

### 4. Reuse the session

Prefer, in order:

1. Reuse the profile directory from future launches
2. Attach automation to the live browser over CDP
3. Export cookies only if the downstream tool truly requires cookies instead of a profile

Avoid reading the browser cookie database directly unless there is no safer path.

When the host login state is ready and the remaining work is ordinary page interaction, screenshots, or DOM inspection, switch back to your browser-interaction companion skill, such as `agent-browser`.

### 5. Shut the stack down

Default behavior after verification:

- Stop the stack if the saved profile is enough for the next step
- Keep it running only while a live CDP handoff is still required

Run:

```bash
scripts/browser-login-stack.sh stop
```

## Fast Troubleshooting

- User sees `ERR_CONNECTION_TIMED_OUT`: verify local host health with `status`; if host-side noVNC is healthy, use SSH port forwarding.
- `status` shows ports already in use: stop the old stack or choose different ports.
- Chrome only listens on `127.0.0.1:9222`: this is normal; use SSH port forwarding for user-side DevTools.
- Background jobs disappear in the agent shell: use the script; if needed, follow `references/manual-fallback.md`.
- The host is already logged in and now the task is just browser interaction: stop using this skill and continue with your installed browser-interaction companion skill.

## Completion Checklist

- Dependencies exist or the user installed them
- Stack health is confirmed with `status`
- User completed login in the host browser
- Agent re-verified the logged-in page from the host
- Profile or CDP reuse path is recorded
- Stack is stopped unless a live browser handoff is still needed
