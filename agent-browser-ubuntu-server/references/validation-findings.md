# Validation Findings

Current automated validation:

- `test_session_manifest.sh`: passes
- `test_cdp_eval.sh`: passes
- `test_browser_runtime.sh`: passes
- `test_assisted_session.sh`: passes
- `test_runtime_common.sh`: passes
- `test_open_protected_page.sh`: passes

Manual wrapper validation on Ubuntu Server host:

- `scripts/open-protected-page.sh --url 'https://foxcode.rjj.cc/api-keys' --origin 'https://foxcode.rjj.cc' --session-key foxcode-main`
- current observed result on 2026-03-13: wrapper correctly reports `needs-user` with a noVNC URL when the reused host-side session drifts back to a login wall
- runtime isolation, target selection, and noVNC URL reporting were all exercised on the real host

Real OpenClaw validation on 2026-03-13:

- the managed skill loads from `~/.openclaw/skills/agent-browser-ubuntu-server/`
- `openclaw agent --json` completes after Gateway fallback to embedded mode
- OpenClaw still returned page quota values for `foxcode.rjj.cc`

Remaining risk:

- host-side wrapper and OpenClaw retest currently disagree about whether the saved `foxcode-main` session is still directly reusable
- `cdp-eval.py --eval` can observe page text that is more accurate than the current `page-info` snapshot on some transitions, so delayed redirects remain the main area to watch in future real-site testing
