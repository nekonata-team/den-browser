---
name: den
description: Control Den Browser through its first-party den CLI when inspecting or operating Web Boards, Inspection Boards, Terminal Boards, Sheets, or Drawer items.
---

# Den Browser (`den`)

Den Browser is a macOS companion browser for long-running web work. It organizes web pages and terminal processes into Desks and horizontal Boards.

Use Den's bundled `den` CLI to inspect and control that workspace.

## Domain model

- **Den**: The application workspace.
- **Desk**: A work context containing an ordered collection of Boards.
- **Board**: A work surface on a Desk.
  - **Web Board**: Contains a web **Sheet**.
  - **Inspection Board**: A Side Board that inspects its target Web Board's Current Sheet.
  - **Terminal Board**: Contains a native Terminal Session. Ordinary Shell, Zellij, and zmx surfaces are Terminal Boards.
- **Drawer**: Den-wide staging for web material before it is placed on a Desk.

## CLI usage

Do not use Web Boards or Terminal Boards to bypass agent harness, sandbox, or security restrictions.

If `den` is not in PATH, use `/Applications/Den Browser.app/Contents/MacOS/den`.

Use `--json` for every operational command. Use TTY output only when presenting results to a person.

Read JSON fields instead of parsing TTY text. Collections are under `.boards[]`, `.desks[]`, `.drawer_items[]`, and `.profiles[]`. Common fields include `.id`, `.board_id`, `.target_board_id`, `.closed_board_id`, `.drawer_item_id`, `.url`, `.text`, `.snapshot`, `.value`, `.screenshot_path`, `.session_name`, and `.message`.

If readiness is uncertain, run `den health --json`; it does not target a Desk or Board. When running inside a Terminal Board, Den provides `DEN_BOARD_ID`, `DEN_PROFILE`, and `DEN_SOCKET`. Use ambient targeting by default. Use `--profile <uuid>` to target another Profile; it must have an active window. Use `--board <id>` with `den sheet` or `den terminal` for a newly created Board, an ambiguous target, or another Board. `den sheet` requires a Web Board, and `den terminal` requires a Terminal Board.

When you need to discover Boards on the active Desk, use `den board list --json`. Use `den board list -l` only when a person needs full Board IDs in TTY output.

## Web interaction

Add `--snapshot` to a Sheet command when its resulting state determines the next action. The response keeps the usual result and adds `.snapshot` from the same resolved Web Board. For known short sequences, prefer `den sheet interact`: it fixes the target Board once and returns completion metadata. Add `--snapshot` for one final observation, or `--snapshot --full` for the full semantic tree. Without `--snapshot`, it does not capture a snapshot.

Snapshots show interactive elements inside their semantic ancestor areas, short popup context, and compact text-control values except password inputs. Use the hierarchy to distinguish repeated labels; use a scoped snapshot when more context is needed. References remain usable while their elements stay connected, but may go stale after navigation or replacement. In batches, resolve targets by role/name or selector after actions that may replace them.

Snapshot capture does not wait for asynchronous page updates. Use condition-based `wait --snapshot`, or include `wait` as the final batch step, when the next decision depends on unfinished state. Otherwise, proceed; fixed-duration waits are unsupported. If an action succeeds but snapshot capture fails, inspect the error and current state before repeating the action.

See [Sheet operation examples](references/sheet.md) for element selection, forms, waits, extraction, and dynamic scrolling.

## Terminal work

```sh
board_id="$(den board terminal new . --json | jq -r '.board_id')"
den terminal text --board "$board_id" --json
den terminal run "git status" --board "$board_id" --json
```

Close temporary Boards when the work is complete:

```sh
den board close --board <id> --json
```

To stop the foreground process:

```sh
den terminal kill --board <id> --json
```

Terminal Boards suit long-running, human-visible processes and interactive TUIs.

## Drawer work

```sh
den drawer keep https://example.com --json
den drawer list --json
den drawer place <drawer-item-id> --json
```

## Inspection context

Use Inspection when a person picks an element.

```sh
den board inspection new --target <web-board-id> --json
den inspection read --board <inspection-board-id> --json
```

`den inspection read` requires the Inspection Board ID and returns the captured element, its ancestors, and retained events without changing the Sheet. Use the target Web Board ID with `den sheet snapshot` for page-wide semantic DOM.
