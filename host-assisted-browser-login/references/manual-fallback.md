# Manual Fallback

Use this only when `scripts/browser-login-stack.sh` is insufficient or when debugging the stack itself.

## Manual Start Sequence

Create isolated directories:

```bash
mkdir -p "$HOME/.remote-browser-profile" "$HOME/.remote-browser-logs"
```

Start `Xvfb` on a dedicated display such as `:77`:

```bash
Xvfb :77 -screen 0 1600x900x24 -ac +extension RANDR
DISPLAY=:77 xdpyinfo | sed -n '1,15p'
```

Start VNC bound to host localhost:

```bash
env DISPLAY=:77 x11vnc -display :77 -forever -shared -rfbport 5900 -localhost -nopw
```

Expose noVNC:

```bash
websockify --web=/usr/share/novnc 0.0.0.0:6080 localhost:5900
```

Start the browser:

```bash
env DISPLAY=:77 google-chrome \
  --no-first-run \
  --no-default-browser-check \
  --user-data-dir="$HOME/.remote-browser-profile" \
  --remote-debugging-address=0.0.0.0 \
  --remote-debugging-port=9222 \
  --new-window 'https://example.com'
```

If `google-chrome` is unavailable, substitute the detected Chromium binary.

## Manual Health Checks

```bash
lsof -iTCP -sTCP:LISTEN -P -n | rg '5900|6080|9222'
curl -I -s http://127.0.0.1:6080/vnc.html | sed -n '1,5p'
curl -s http://127.0.0.1:9222/json/version
curl -s http://127.0.0.1:9222/json/list
```

## Windows User Access

Direct noVNC:

```text
http://HOST_IP:6080/vnc.html?autoconnect=1&resize=remote
```

Preferred if direct access is blocked:

```powershell
ssh -L 6080:127.0.0.1:6080 -L 9222:127.0.0.1:9222 USER@HOST_IP
```

Then open:

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote
http://127.0.0.1:9222/json
chrome://inspect
```

## Verification Notes

After the user reports login success, re-check the actual target URL from the host browser session. Some sites show generic 404 or placeholder pages before authentication, so revisit the exact URL after login before deciding it is missing.

## Common Problems

### `ERR_CONNECTION_TIMED_OUT`

If `127.0.0.1:6080` returns `HTTP 200` on the host but the user times out remotely, the problem is usually network reachability or host firewall policy. Use SSH port forwarding first.

### `Xvfb` fails to stay up

- Keep it in a dedicated PTY session
- Verify with `DISPLAY=:77 xdpyinfo`
- Remove stale lock files only after confirming no active X server owns that display

### Existing listeners remain after shutdown

Manual sessions or old runs may still hold ports. Inspect listeners and terminate the leftover processes before restarting on the same ports.
