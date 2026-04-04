# Assisted LAN Flow

- Assisted recovery assumes the browser runtime is already running in GUI mode and exposes a valid X display
- `assist-lan-session.sh start` attaches `x11vnc` to that display and serves noVNC through `websockify`
- The operator URL is LAN-only and fixed to port `6084` by default; constrained/container environments should set `AGENT_BROWSER_NOVNC_PUBLIC_HOST` explicitly to a LAN-reachable host or IP
- `start` and `status` return JSON handoff payloads with `status: needs-user`, `next_action: open-novnc`, `operator_required: true`, `operator_url`, `lan_novnc_url`, `resume_command`, and `message_for_agent`
- `open-host-page.sh` uses assisted mode as a handoff: on `challenge`, `login-wall`, or unrecovered `target-mismatch`, it returns the same explicit handoff contract and does not auto-capture before operator takeover
- When the blocker is a challenge page such as Cloudflare Turnstile or reCAPTCHA, the agent should surface `operator_url` or `lan_novnc_url` to the user, tell them to complete the challenge in that browser session, and resume only through `resume_command`
- `capture` returns JSON with `status: ready`, `next_action: none`, `operator_required: false`, and `capture_completed: true`
- `stop` returns JSON with `status: stopped`, `next_action: none`, `operator_required: false`, and `assisted_session_stopped: true`
- `capture` inspects the live runtime target (`list-targets` + `select-target` + `check-page`) and refuses to persist reusable state while challenge/login-wall/off-origin drift is still present
- when `--target-url` is provided, capture requires the final page URL to match that requested target URL exactly; otherwise capture falls back to same-origin verification
- successful `capture` writes:
  - session manifest at `--manifest-root`
  - site session registry at the main skill root (`$HOME/.agent-browser/index/site-sessions.json`)
  - identity providers at the main skill root (`$HOME/.agent-browser/index/identity-profiles.json`)
