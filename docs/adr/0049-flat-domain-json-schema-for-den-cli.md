---
status: accepted
---

# Flat Domain JSON Schema for `den` CLI and IPC

Den Browser defines a structured, flat domain JSON schema for its inter-process communication (IPC) protocol and command-line tool (`den`).

## Context and Problem

The initial CLI prototype bundled response payloads into an untyped generic string wrapper (`{"success": true, "result": "..."}`). While expedient for early prototyping, this design imposed several structural friction points:
1. Structured list queries (`den board list`, `den desk list`) returned multiline formatted strings inside the JSON payload, preventing Unix piping tools (`jq`) and autonomous agents from extracting IDs, labels, or active states without brittle regex parsing.
2. Creation commands returned bare UUID strings inside `result`, obscuring the semantic identity of the output.
3. IPC responses lacked self-describing field keys, requiring client code to rely on implicit positional assumptions.

## Decision

Den Browser replaces the untyped `result` envelope with a typed, flat domain schema utilizing `snake_case` keys:

1. **Top-Level Protocol Envelope**:
   - Every IPC response provides `ok: Bool`.
   - On error, `ok` is `false`, `error` contains a descriptive diagnostic message, and the CLI exits with non-zero status.
   - On success, `ok` is `true`, and domain-specific properties are exposed directly at the top level without intermediate nesting wrappers (`data` or `result`).

2. **Domain-Specific Payloads**:
   - **Board Creation (`board web new`, `board terminal new`)**: Returns `board_id` (`String`).
   - **Board Closure (`board close`)**: Returns `closed_board_id` (`String`) and confirmation `message`.
   - **Board Query (`board list`)**: Returns `boards` array of `DenBoardInfo` objects (`id`, `type`, `label`, optional `url`, optional `session_name`).
   - **Desk Query (`desk list`)**: Returns `desks` array of `DenDeskInfo` objects (`id`, `label`, `is_active`, `board_count`).
   - **Sheet Inspection**:
     - `sheet url`: Returns `url` (`String`).
     - `sheet text`: Returns `text` (`String`).
     - `sheet eval`: Returns `value` (`String`).
     - `sheet snapshot`: Returns `snapshot` (`String`), retaining compact accessibility tree formatting to conserve agent context tokens.
     - `sheet screenshot`: Returns `screenshot_path` (`String`).
   - **Sheet Actions (`click`, `fill`, `press`, `scroll`, `wait`, `open`, `reload`)**: Return `ok: true` alongside human-readable `message`.

3. **Dual Human and Machine Ergonomics**:
   - **Interactive Terminal (TTY)**: Emits clean, readable standard output (e.g. raw UUID for `board web new`, multi-column table for `board list`, raw semantic tree for `snapshot`).
   - **Piped / Non-TTY / `--json`**: Emits compact, single-line JSON directly parseable with `jq` in a single level:
     ```bash
     BOARD_ID=$(den board web new https://example.com | jq -r .board_id)
     WEB_BOARDS=$(den board list | jq -r '.boards[] | select(.type == "web") | .id')
     URL=$(den sheet url | jq -r .url)
     ```
