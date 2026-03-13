# Validation Findings

Current local validation:

- `test_session_manifest.sh`: passes
- `test_cdp_eval.sh`: passes
- `test_browser_runtime.sh`: passes
- `test_assisted_session.sh`: passes

Pending higher-confidence validation before promotion:

- Real browser dependency check on an Ubuntu Server host with Chrome or Chromium installed
- Manual `browser-runtime.sh start --mode headless` dry-run
- Manual `browser-runtime.sh start --mode gui` dry-run
- Manual assisted noVNC overlay check with `x11vnc` and `websockify`
- One real challenge page and one login-wall page verification
