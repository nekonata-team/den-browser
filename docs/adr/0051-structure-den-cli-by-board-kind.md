---
status: accepted
---

# Structure `den` CLI by Board Kind

## Context and Problem

Den has one Board collection on each Desk, but Web Boards and Terminal Boards expose different operations. The CLI previously mixed Board creation with Sheet and Terminal Session commands, and exposed the Board target option on commands that could not use it. `board close` also accepted both a positional Board ID and `--board`, allowing two competing target sources.

## Decision

- Keep common Board operations under `den board`: `list`, `focused`, and `close`.
- Put creation and kind-specific operations under `den board web`, `den board terminal`, and `den board inspection`.
- Use `new` for Board creation and `navigate` for URL or search navigation within an existing Web Board's Sheet Stack.
- Treat shell, Zellij, and zmx surfaces as Terminal Boards; their backend kind remains an internal detail of the Terminal Board.
- Keep `--json` and `--socket` as common CLI options. Expose `--board` only on commands that target an existing Board: Web Sheet operations, Terminal Session operations, `den board inspection read`, and `den board close`.
- Use `--board` for an explicit Board target. Keep positional IDs for other resources such as Drawer Items. `den board close` rejects positional arguments.

## Consequences

The CLI makes the Board kind explicit for operations on Web and Terminal Boards. Creating a Board requires a longer command, but invalid target options and ambiguous Board ID forms are removed. The Desk can continue to store Web and Terminal Boards in one ordered collection, which preserves spatial adjacency and ambient targeting.
