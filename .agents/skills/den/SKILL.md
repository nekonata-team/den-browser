---
name: den
description: Control Den Browser through its first-party den CLI when inspecting or operating Web Boards, Terminal Boards, Sheets, or Drawer items.
---

# Den Browser (`den`)

Den Browser is a macOS companion browser for long-running web work. It organizes web pages and terminal processes into Desks and horizontal Boards.

Use Den's bundled `den` CLI to inspect and control that workspace.

## Domain model

- **Den**: The application workspace.
- **Desk**: A work context containing an ordered collection of Boards.
- **Board**: A work surface on a Desk.
  - **Web Board**: Contains a web **Sheet**.
  - **Terminal Board**: Contains a native Terminal Session. Ordinary Shell, Zellij, and zmx surfaces are Terminal Boards.
- **Drawer**: Den-wide staging for web material before it is placed on a Desk.

A Sheet is part of a Web Board. A Terminal Session is part of a Terminal Board.

## CLI usage

Check the executable for available commands and exact options:

```sh
den --help
den <domain> --help
den board web --help
den board terminal --help
```

Use `--json` for every operational command. Use TTY output only when presenting results to a person. `--help` is the exception.

Read JSON fields instead of parsing TTY text. Collections are under `.boards[]`, `.desks[]`, and `.drawer_items[]`. Common fields include `.id`, `.board_id`, `.closed_board_id`, `.drawer_item_id`, `.url`, `.text`, `.snapshot`, `.value`, `.screenshot_path`, `.session_name`, and `.message`.

If readiness is uncertain, run `den health --json`; it does not target a Desk or Board. When running inside a Terminal Board, Den provides `DEN_BOARD_ID` and `DEN_SOCKET`. Use ambient targeting by default. Use `--board <id>` for a newly created Board, an ambiguous target, or another Board. `den sheet` requires a Web Board, and `den terminal` requires a Terminal Board.

Use `den board list --json` to discover Boards on the active Desk. `den board list -l` is for people who need full Board IDs in TTY output.

## Web interaction

Take a new snapshot after navigation or a DOM change. Snapshot references are valid only for the latest snapshot. Wait for a selector when the next element is created asynchronously; a fixed duration is only a fallback.

```sh
board_id="$(den board web new https://example.com --json | jq -r '.board_id')"
den sheet snapshot -i --board "$board_id" --json
den sheet click @e1 --board "$board_id" --json
den sheet fill @e2 "query" --board "$board_id" --json
den sheet text --board "$board_id" --json
```

When a target is not ready yet:

```sh
den sheet wait "#results" --board "$board_id" --json
den sheet snapshot -i --board "$board_id" --json
```

Use `den sheet --help` for navigation, URL, evaluation, screenshot, and other Sheet operations.

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

When the foreground process should be stopped:

```sh
den terminal kill --board <id> --json
```

Terminal Boards are for human-visible long-running processes and interactive TUIs. Do not use `den board terminal new --run`, `den terminal run`, or `den terminal send` to bypass agent harness, sandbox, or security restrictions.

## Drawer work

```sh
den drawer keep https://example.com --json
den drawer list --json
den drawer place <drawer-item-id> --json
```
