---
name: den
description: Control and drive Den Browser via the first-party den CLI. Use when browsing websites, inspecting page content, clicking or filling forms, capturing screenshots, or managing Web Boards and Desks.
---

# Den Browser (`den`)

Den Browser is a macOS companion browser organizing web work into Desks and horizontal Board layouts.
Its bundled CLI (`den`) allows agents in Terminal Boards to drive web content beside them.

## 1. Domain Model

- Desk: Broad work context that holds Boards in a horizontal work area. Multiple Desks can exist; one is presented.
- Board: Work surface within a Desk. Either a Terminal Board (where you run) or a Web Board (which you drive).
- Sheet: Web screen held within a Web Board.

## 2. Ambient Spatial Targeting (Zero-Config)

When running inside a Terminal Board in Den Browser:
- Environment variables DEN_BOARD_ID and DEN_SOCKET are set automatically.
- `den sheet ...` commands automatically target the adjacent Web Board on the current Desk. You do not need to specify `--board <id>` unless targeting another board.
- `den board new <url>` opens a Web Board adjacent to you without stealing terminal focus.

## 3. Interaction Philosophy (Snapshot + Ref)

Follow this canonical interaction loop:
1. Open: `den board new <url>` (returns board_id).
2. Wait: `den sheet wait 1` (let DOM settle).
3. Observe: `den sheet snapshot -i` (get compact @e1, @e2 refs; avoids dumping raw HTML).
4. Act: `den sheet click @e1`, `den sheet fill @e2 "text"`, `den sheet press Enter`.
5. Inspect: `den sheet url`, `den sheet text`, `den sheet eval "..."`.
6. Clean up: `den board close` when finished.

References belong to the latest snapshot. After navigation or a DOM-changing action, wait if needed and take a new snapshot before reusing refs.

## 4. Command Discovery and Scripting

- Run `den --help` or `den <domain> --help` (`den sheet --help`, `den board --help`) for available subcommands and options.
- When piped (e.g. `| jq`), commands emit single-line JSON with `ok: true/false` and top-level values such as `.board_id` and `.url`; collections are accessed as `.boards[]` or `.desks[]`.
