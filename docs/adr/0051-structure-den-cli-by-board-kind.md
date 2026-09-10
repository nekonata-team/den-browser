---
status: accepted
---

# Structure `den` CLI by Board Kind

## Context and Problem

Den has one Board collection on each Desk, but Web Boards and Terminal Boards expose different operations. The CLI previously mixed Board creation with Sheet and Terminal Session commands, and exposed the Board target option on commands that could not use it. `board close` also accepted both a positional Board ID and `--board`, allowing two competing target sources.

## Decision

- Keep common Board operations under `den board`: `list` and `close`.
- Put Board-kind operations under `den board web` and `den board terminal`.
- Keep Sheet operations under `den sheet` and Terminal Session operations under `den terminal`.
- Treat shell, Zellij, and zmx surfaces as Terminal Boards; their backend kind remains an internal detail of the Terminal Board.
- Keep `--json` and `--socket` as common CLI options. Expose `--board` only on commands that target a Board: Sheet commands, Terminal Session commands, and `den board close`.
- Use `--board` for an explicit Board target. Keep positional IDs for other resources such as Drawer Items. `den board close` rejects positional arguments.
- Represent IPC commands as the same nested domain Enum on both sides and let Swift synthesize their `Codable` representation.

## Consequences

The CLI makes the distinction between a Board, a Web Board, a Sheet, a Terminal Board, and a Terminal Session visible in its command paths. Creating a Board requires a longer command, but invalid target options and ambiguous Board ID forms are removed. The Desk can continue to store Web and Terminal Boards in one ordered collection, which preserves spatial adjacency and ambient targeting.
