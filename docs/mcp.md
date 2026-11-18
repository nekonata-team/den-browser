# Den MCP Server (`den mcp`)

Run `den mcp [--socket <path>] [--profile <uuid>]` as a local stdio server. The MCP client owns the process. The server uses a user-scoped Unix socket to reach a running Den Browser. Socket resolution checks `--socket`, `DEN_SOCKET`, then `~/.den/den.sock`. Profile scope comes from `--profile` or `DEN_PROFILE`; with neither set, calls use the active Profile unless an explicit Board or action ref identifies its Profile. Ambient operations use the presented Desk and ignore `DEN_BOARD_ID`. Starting the server and listing tools work without a running Den Browser and do not open a window.

```json
{
  "mcpServers": {
    "den": {
      "command": "/Applications/Den Browser.app/Contents/MacOS/den",
      "args": ["mcp"]
    }
  }
}
```

## Tools

| Tool | Arguments | Result and effect |
|---|---|---|
| `overview_den` | None | Ordered Desks and Boards for the selected Profile, `active_desk_id`, `focused_board_id` when present, and saved `desk_presets`. Each Board appears in its Desk only. |
| `search_den` | `query`, optional `kinds`, optional `limit` (1–20, default 5) | Ordered Universal Search matches with `kind`, `name`, `location`, optional `id` and `detail`, and `actions`. Leaves focus and layout untouched. |
| `act_on_result` | `ref` | Executes the single-step action described by its ref. |
| `move_board` | `board_id`, one of `desk_id`, `left_of`, `right_of` | Moves a Board Group to the end of a Desk or beside another Board without searching first. |
| `create_desk` | `name`, optional `preset`, optional `focus` (default false) | Creates a Desk from a built-in preset (`empty`, `chatGPT`, `gemini`) or a Personal Desk Preset label or UUID. |
| `open_pages` | `pages` (1–20 entries), optional `desk` or `new_desk` | Appends new Web Boards in input order. Returns the destination Desk and the result of each entry. Leaves the presented Desk, the original Boards, and any existing focus in place. |
| `read_page` | Optional `board_id` or `url` | Returns `title`, actual `url`, `markdown`, and `board_id`. With neither argument it reads the focused Web Board. A URL creates a Web Board on the presented Desk without selecting it. The Board is retained if reading fails. Retry with the returned `board_id`. |
| `read_selection` | Optional Inspection `board_id` | Reads the human's selected element, ancestors, source URL and Board, document identity, timestamps, and connection state. Prefers the focused Inspection Board or the one attached to the focused Board. If there are multiple other Inspection Boards, returns choices. Leaves focus and selection in place. |
| `read_terminal` | Optional Terminal `board_id`, optional `lines` (≥ 1) | Reads visible screen text or the last N retained lines from a Terminal Board without changing focus. Omit `board_id` for the focused Terminal Board. |
| `list_notifications` | Optional `unread_only` (default false) and `limit` (1–20, default 5) | Lists retained Notifications for the current Profile, newest first. Filters before applying the limit and preserves read state. |

Tool results contain `structuredContent` and its JSON text representation. Call failures set `isError` and may include recoverable details, such as a newly created `board_id` or failed entries. Choices and previews are successful calls and describe what to pass next.

## Search and act

Search for a Board or Desk by name, keywords, or ID. Universal Search applies its existing matching and order, with actions for showing and closing Boards, showing and removing Desks, and creating Web Boards from Recent, Essentials, or the search input. A Board match shows an existing Board. A Recent match creates a new one. Use `create_desk` to create a Desk and `move_board` to move or reorder a Board Group.

Use `act_on_result` with the advertised ref. Action refs bind the Profile, target, and effect. They are temporary and may expire during an app run. Missing or changed targets (including Desk contents changed since the search) return an error prompting a fresh search. The last Desk is retained.

## Open and read pages

Supply absolute HTTP, HTTPS, or local file URLs. The special `"current"` entry in `open_pages` captures the focused Web Board's URL at the start of the call. Omit `desk` and `new_desk` to append to the presented Desk. Supply a Desk label or UUID as `desk` to use an existing Desk, or a label as `new_desk` to create one. If several Desk labels match, the result contains `choices` with Desk IDs and the call makes no changes.

An `open_pages` result lists each original input with its zero-based `index`. A successful entry has a `board_id`; an unsuccessful entry has an `error`. Retry only failed entries with the returned Desk ID. Creating a Web Board and reading the loaded page are separate operations.

For the Inspection payload's freshness fields, see [Reading inspection context](inspection.md#reading-inspection-context-with-den).

## Migrating from the previous MCP catalog

| Previous tools | Use instead |
|---|---|
| `inspect_den` | `overview_den`; use `den overview` for the CLI's full Profile and ambient Board fields. |
| `create_web_board`, `close_board` | `open_pages`, or find the relevant action using `search_den`. |
| `read_sheet_markdown`, `read_sheet_text`, `read_inspection` | `read_page` or `read_selection`; use `den board web read`, `den board web text`, or `den board inspection read` for the previous options. |
| `open_profile`, `create_inspection_board`, `open_sheet`, `inspect_sheet`, other Sheet tools | `den profile open`, `den board inspection new`, and `den board web` subcommands. |
| Drawer and Terminal tools | `read_terminal` for reading Terminal output; `den drawer` and `den board terminal` subcommands for Drawer and interactive Terminal control. |

See the [CLI reference](cli.md) and [MCP catalog decision](adr/0074-ground-mcp-in-universal-search.md).
