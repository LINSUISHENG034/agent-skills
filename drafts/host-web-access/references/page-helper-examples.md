# Page Helper Examples

## Copyable Commands

- Inspect the current page:
  `host-page-ops.py --check page-info`
- Retry a page-info check on a dynamic page:
  `host-page-ops.py --check page-info --retry 3 --retry-delay-ms 400`
- Evaluate a JS expression:
  `host-page-ops.py --eval "document.title"`
- Navigate and wait for the next page load:
  `host-page-ops.py --navigate "https://example.com" --wait-navigation`
- Click a visible link by text:
  `host-page-ops.py --click-link-text "Pricing"`
- Capture the current page as markdown:
  `host-page-snapshot.py --format markdown`

## Shell-Safe Invocation

- Pass related flags in the same command invocation.
- Quote URLs, selectors, and JS expressions so the shell passes them as single arguments.
- Do not split `--wait-navigation` onto its own shell line; that makes the shell try to run `--wait-navigation` as a separate command.

Correct:

```bash
host-page-ops.py --navigate "https://example.com" --wait-navigation
```

Incorrect:

```bash
host-page-ops.py --navigate "https://example.com"
--wait-navigation
```
