#!/usr/bin/env bash
set -euo pipefail

latest_mode=false
article_mode=false
dynamic_mode=false
protected_mode=false
interactive_mode=false
login_mode=false
host_browser_mode=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --latest)
      latest_mode=true
      ;;
    --article)
      article_mode=true
      ;;
    --dynamic)
      dynamic_mode=true
      ;;
    --protected)
      protected_mode=true
      ;;
    --interactive)
      interactive_mode=true
      ;;
    --login-required)
      login_mode=true
      ;;
    --host-browser)
      host_browser_mode=true
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      ;;
  esac
  shift
done

route="extract"
reason="default"
needs_browser=false

if "$host_browser_mode"; then
  route="browser"
  reason="host-browser-requested"
  needs_browser=true
elif "$protected_mode"; then
  route="browser"
  reason="protected-site"
  needs_browser=true
elif "$interactive_mode"; then
  route="browser"
  reason="interaction-required"
  needs_browser=true
elif "$dynamic_mode"; then
  route="browser"
  reason="dynamic-rendering"
  needs_browser=true
elif "$login_mode"; then
  route="browser"
  reason="login-required"
  needs_browser=true
elif "$article_mode"; then
  route="fetch"
  reason="public-article"
else
  route="search"
  reason="latest-info"
fi

printf '{"route": "%s", "reason": "%s", "needs_browser": %s}\n' \
  "$route" "$reason" "$needs_browser"
