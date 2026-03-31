# Validation Findings

- Local validation completed on the consolidated draft worktree. Fresh verification commands all exited 0:
  - `bash drafts/host-web-access/scripts/test_runtime_common.sh`
  - `bash drafts/host-web-access/scripts/test_session_manifest.sh`
  - `bash drafts/host-web-access/scripts/test_site_session_registry.sh`
  - `bash drafts/host-web-access/scripts/test_profile_resolution.sh`
  - `bash drafts/host-web-access/scripts/test_browser_runtime.sh`
  - `bash drafts/host-web-access/scripts/test_assist_lan_session.sh`
  - `bash drafts/host-web-access/scripts/test_host_page_ops.sh`
  - `bash drafts/host-web-access/scripts/test_host_page_snapshot.sh`
  - `bash drafts/host-web-access/scripts/test_route_web_task.sh`
  - `bash drafts/host-web-access/scripts/test_open_host_page.sh`
  - `python3 -m py_compile drafts/host-web-access/scripts/host-cdp-core.py drafts/host-web-access/scripts/host-page-ops.py drafts/host-web-access/scripts/host-page-snapshot.py`
- Task coverage: runtime lifecycle, local CDP ownership, assisted LAN recovery, profile resolution, router behavior, and the integrated open-host-page entry path each have a local verification command
- Assisted recovery: `test_assist_lan_session.sh` confirms the fixed LAN port `6084`, status output only reports `lan_novnc_url`, capture writes the manifest/site registry, and stop releases assisted runtime state
- Integrated flow: `test_open_host_page.sh` validates lightweight routing vs browser escalation, confirms `profile-resolution.sh resolve` is called before browser startup, exercises assisted capture when the runtime is not running, and ensures cleanup is always invoked
- Cleanup invariants: `cleanup-host-runtime.sh` stops browser/Xvfb/x11vnc/websockify PIDs if present and rewrites runtime metadata to `STATE=closed` without touching persistent profiles
- Real-host validation is still pending. The draft has not yet been validated against an actual Ubuntu host browser session and a Windows LAN client in this worktree.
