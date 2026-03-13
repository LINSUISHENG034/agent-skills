# Testing Matrix

## Should Trigger

- "Open this Cloudflare-protected site from the Ubuntu server and tell me what it shows."
- "Reuse the same browser session from yesterday's server run."
- "This dashboard on the Ubuntu host is stuck on Verify you are human. Recover it."
- "Browse x.com from the server and tell me if I need to log in."
- "Use the old verified server-side browser instead of launching a fresh one."
- "Use the Ubuntu host browser skill to open this protected page and tell me whether it needs noVNC help."

## Should Not Trigger

- "Search the web for the latest Ubuntu release notes."
- "Fetch this public JSON API and summarize it."
- "Open this site in my local desktop browser."
- "Help me write a curl command for this endpoint."
- "Summarize the HTML I already pasted here."

## Special Trigger Reviews

- Same-origin multi-session recovery: "Reuse the `acct-b` session for `https://example.com` instead of the other saved one."
- Direct-browse path: "Open `https://example.com` on the Ubuntu host and tell me the page title if it loads publicly."
- High-level wrapper path: "Open `https://foxcode.rjj.cc/api-keys` from the Ubuntu host and reuse the existing verified session if possible."
