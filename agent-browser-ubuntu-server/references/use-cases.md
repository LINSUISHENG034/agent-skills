# Use Cases

## 1. First-Time Protected-Site Access

User intent: open a site from a headless Ubuntu Server host and inspect or interact with the page, even if the site presents Cloudflare, CAPTCHA, or login challenges.

Representative requests:

- "Open this site on the server and tell me what the page shows."
- "Browse this dashboard from the Ubuntu host."
- "Check whether this protected page loads from the agent host."

Desired result: the skill either opens the page directly or asks for one bounded round of user help to establish a reusable browser session.

## 2. Reuse An Existing Verified Session

User intent: continue using the same browser context that already passed verification earlier.

Representative requests:

- "Go back to the same site and read the latest content."
- "Continue browsing that dashboard from yesterday's session."
- "Reuse the same verified browser on the Ubuntu server."

Desired result: the skill reattaches to the recorded browser context and avoids unnecessary new verification prompts.

## 3. Recover A Degraded Session

User intent: the current browser state has drifted back to a challenge page, login wall, or dead browser process and needs the lightest possible recovery path.

Representative requests:

- "This page is back on Verify you are human. Recover it if possible."
- "The old session stopped working. Re-establish access with the least user help."
- "Try the existing session first, then tell me exactly what I need to do."

Desired result: local recovery happens first, user assistance only happens when the existing session is irrecoverable.
