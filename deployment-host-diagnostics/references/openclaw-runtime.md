# OpenClaw Runtime Checks

Use these commands when the user is asking about the deployment runtime, gateway health, channels, service state, or whether OpenClaw itself is up.

## Primary checks

```bash
openclaw gateway status
openclaw channels status --probe
openclaw security audit --deep
openclaw doctor
```

Use `openclaw logs --follow` only when the user explicitly wants live log streaming or when a point-in-time check was insufficient.

## Service details

```bash
systemctl --user status openclaw-gateway.service --no-pager
systemctl --user show -p MainPID,ActiveState,SubState openclaw-gateway.service
cat ~/.config/systemd/user/openclaw-gateway.service
```

## Local gateway reachability

```bash
ss -ltnp | rg 18789
curl -sS http://127.0.0.1:18789/ | head
```

## Session and state files

```bash
find ~/.openclaw/agents -path '*/sessions/*.jsonl' -type f | sort | tail
tail -n 80 ~/.openclaw/agents/<agent-id>/sessions/<session-file>.jsonl
```

## Guidance

- Start with `openclaw gateway status` when the question is about overall health.
- Use `openclaw channels status --probe` when the question is about connected channels.
- If session evidence is needed, first identify the active agent and newest session file instead of assuming a fixed path.
- If the user asks which model is active, verify from runtime or session evidence instead of assuming config equals reality.
- When there is a mismatch, explicitly separate:
  - configured model
  - active model
  - fallback behavior seen in logs
