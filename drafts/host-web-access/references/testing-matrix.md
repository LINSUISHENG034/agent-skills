# Testing Matrix

- Runtime common helpers normalize origins, aliases, ports, and display selection
- Session manifest selection stays deterministic and never guesses among multiple sessions
- Site session registry survives broken JSON and still resolves the default session
- Profile resolution prefers site registry, then manifest, then identity/legacy/scoped fallbacks
- Browser runtime reports `stopped` before start, `running` after start, and `closed` after cleanup
- Cleanup is idempotent and safe when no browser resources are active
