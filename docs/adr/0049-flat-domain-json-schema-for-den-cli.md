---
status: accepted
---

# Flat Domain JSON Schema for `den` CLI and IPC

Den's CLI and IPC use a typed, flat JSON schema with `snake_case` domain fields and an `ok` envelope, replacing an untyped `result` string that forced clients to parse formatted text and ambiguous IDs.
Success payloads expose domain fields directly; errors report `ok: false` and a diagnostic, with a nonzero CLI exit status.
TTY output remains human-readable, while pipes and `--json` receive machine-readable JSON; command payloads and examples belong in the [CLI reference](../cli.md).
