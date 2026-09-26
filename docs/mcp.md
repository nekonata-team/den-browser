# Den MCP Server (`den mcp`)

`den mcp` exposes common Den operations as typed MCP tools. Tools reuse Den's operation semantics and typed IPC. Den Browser remains the owner of Profile, Board, Sheet, and Terminal state.

## 1. Tool model

The CLI uses domain-first commands:

```text
den <domain> <action>
```

MCP presents a flat catalog with action-first names:

```text
inspect_den
open_sheet
click_sheet_element
save_url_to_drawer
```

Clients discover JSON Schema inputs and call tools directly; tools do not accept shell command strings. `inspect_den` combines related reads into one consistent result. Other tools map to existing CLI operations where possible. Product terms follow [CONTEXT.md](../CONTEXT.md).

## 2. Server Lifecycle and Transport

`den mcp` runs a local MCP server over standard input and standard output. An MCP client launches the process and owns its lifetime.

```text
den mcp [--socket <path>] [--profile <uuid>]
```

- MCP protocol messages use standard input and standard output. Standard output contains protocol messages only; diagnostics go to standard error.
- The server connects to the running Den Browser app through its existing user-scoped Unix domain socket. Socket resolution follows the CLI: explicit `--socket`, `$DEN_SOCKET`, then `~/.den/den.sock`.
- `DEN_PROFILE` and `DEN_BOARD_ID` are inherited when present. A server launched by an external MCP client may not have ambient Board context.
- The process is not a daemon and does not open a network listener. Closing the client connection ends the server process.
- Tool calls do not depend on session state retained by the MCP server. Each call resolves its target from explicit arguments, launch options, environment, or the active Den context.
- If Den Browser is unavailable, tool calls return a clear error. MCP initialization alone does not imply that Den Browser is ready.

Example client configuration:

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

## 3. Tool Arguments and Targeting

Each tool publishes an `inputSchema`. Clients call a tool by name with an `arguments` object. Invalid or unknown values fail before side effects. For example, `open_sheet` requires a URL and accepts optional targets:

```json
{
  "type": "object",
  "properties": {
    "url": { "type": "string" },
    "profile_id": { "type": "string", "format": "uuid" },
    "board_id": { "type": "string", "format": "uuid" }
  },
  "required": ["url"],
  "additionalProperties": false
}
```

### Common Target Arguments

| Argument | Type | Description |
|---|---|---|
| `profile_id` | UUID string, optional | Overrides server `--profile`. If omitted, Profile resolution follows the CLI rules in [`cli.md`](cli.md). Invalid or windowless explicit Profiles fail without fallback. |
| `board_id` | UUID string, optional | Pins a Board for Sheet and Terminal tools. If omitted, Board resolution follows the CLI rules. Invalid explicit Boards fail without fallback. |

Board-targeted results include their effective `profile_id` and `board_id`. Pass those values to later calls to keep a workflow anchored when focus changes. `open_profile` changes the active Profile Window but not the server's launch options.

Tool-specific constraints:

- `click_sheet_element` accepts `target` or both `role` and `name`; `focus_new_board` requires `open_in_new_board`.
- `read_sheet_element.field` is `text`, `value`, `attribute`, `count`, or `box`; `attribute` requires an attribute name.
- `wait_for_sheet` requires exactly one of `target`, `url`, `text`, or `load_state`. `state` requires `target`. Selector states are `attached`, `visible`, `hidden`, or `detached`; load states follow [`cli.md`](cli.md).
- `query_sheet.fields` accepts `tag`, `role`, `name`, `text`, `value`, `checked`, `disabled`, `selected`, `expanded`, `class`, and `attr:<name>`.
- `read_sheet_state.state` is `visible`, `enabled`, or `checked`. `scroll_sheet` accepts `direction` or `target`, not both; the default direction is `down`.

## 4. Tool Specification (v1)

### 4.1 Den and Profile

| Tool | Arguments | Description | CLI equivalent |
|---|---|---|---|
| `inspect_den` | `[profile_id]` | Aggregate the Profile list, selected Profile, its Desks, Boards on its active Desk, focused Board, and Drawer Item count into one compact result. | `profile list`, `desk list`, `board list`, `board focused`, `drawer list` |
| `open_profile` | `profile_id` | Open a window for a Profile or activate its existing window. | `profile open <uuid>` |

`inspect_den` returns `profiles`, `profile`, `profile_id`, `desks`, `active_desk`, `boards`, `focused_board_id`, and `drawer_item_count`. It resolves the Profile and active Desk once so every field describes the same context. Use `list_drawer_items` to retrieve individual items. It does not switch Desks.

### 4.2 Board and Sheet

| Tool | Arguments | Description | CLI equivalent |
|---|---|---|---|
| `create_web_board` | `url`, `[focus]`, `[profile_id]` | Create a Web Board on the active Desk and return its ID. Accept the CLI's supported URL, hostname, or search-query inputs. | `board web new` |
| `open_sheet` | `url`, `[board_id]`, `[profile_id]` | Navigate the target Web Board's Current Sheet. Accept the same inputs and validation as `sheet open`. | `sheet open` |
| `inspect_sheet` | `[board_id]`, `[profile_id]`, `[full]`, `[within]` | Return the target Board ID, Current Sheet URL, and semantic snapshot. The default snapshot contains interactive elements. | `sheet url`, `sheet snapshot` |
| `read_sheet_text` | `[board_id]`, `[profile_id]` | Read visible text (`innerText`) from the Current Sheet. | `sheet text` |
| `query_sheet` | `selector`, `[visible]`, `[all]`, `[fields]`, `[board_id]`, `[profile_id]` | Return matching elements as structured data. `fields` is an array; defaults are `tag`, `role`, `name`, and `text`. | `sheet query` |
| `read_sheet_element` | `target`, `field`, `[attribute]`, `[board_id]`, `[profile_id]` | Read text, value, an attribute, match count, or bounding box for a target. `attribute` is required when `field` is `attribute`. | `sheet get` |
| `read_sheet_state` | `target`, `state`, `[board_id]`, `[profile_id]` | Check whether a target is visible, enabled, or checked. | `sheet is` |
| `click_sheet_element` | `target` or `role` + `name`, `[exact]`, `[open_in_new_board]`, `[focus_new_board]`, `[board_id]`, `[profile_id]` | Click by snapshot ref, selector, or accessible role and name. Optionally open a clicked link in a new Web Board. | `sheet click` |
| `fill_sheet_field` | `target`, `value`, `[board_id]`, `[profile_id]` | Fill an input, textarea, or editable element. An empty `value` clears it. | `sheet fill` |
| `type_sheet_text` | `text`, `[target]`, `[board_id]`, `[profile_id]` | Type text into a target or the currently focused element. | `sheet type` |
| `press_sheet_key` | `key`, `[board_id]`, `[profile_id]` | Dispatch a supported key to the active element. | `sheet press` |
| `scroll_sheet` | `[direction]` or `[target]`, `[board_id]`, `[profile_id]` | Scroll by direction or bring a target into view. The default direction is `down`. | `sheet scroll` |
| `wait_for_sheet` | Exactly one of `target`, `url`, `text`, or `load_state`; `[state]`, `[timeout_seconds]`, `[board_id]`, `[profile_id]` | Wait for a target state, URL, visible text, or supported load state. The default timeout is 10 seconds. | `sheet wait` |
| `navigate_sheet_history` | `direction` (`back` or `forward`), `[board_id]`, `[profile_id]` | Navigate the Sheet Stack backward or forward. | `sheet back`, `sheet forward` |
| `reload_sheet` | `[board_id]`, `[profile_id]` | Reload the Current Sheet. | `sheet reload` |
| `close_board` | `board_id`, `[profile_id]` | Remove the specified Board from its Desk and end its live runtime. A Board ID is required. | `board close --board <id>` |

Sheet references such as `@e1` are document-scoped. They remain usable across operations in the same document and are regenerated when navigation replaces the document. Use the `board_id` returned from `inspect_sheet` for subsequent Sheet calls.

### 4.3 Drawer

| Tool | Arguments | Description | CLI equivalent |
|---|---|---|---|
| `list_drawer_items` | `[profile_id]` | List Drawer Items by ID, title, and URL. | `drawer list` |
| `save_url_to_drawer` | `url`, `[title]`, `[profile_id]` | Keep a supported URL in the Den-wide Drawer without changing Desk layout. Search queries are not accepted. | `drawer keep` |
| `place_drawer_item` | `item_id`, `[profile_id]` | Place a Drawer Item onto the active Desk as a Web Board and return its Board ID. | `drawer place` |
| `discard_drawer_item` | `item_id`, `[profile_id]` | Discard a Drawer Item without placing it. It remains available through Den's current-run Drawer restoration history. | `drawer discard` |

### 4.4 Terminal Boards

| Tool | Arguments | Description | CLI equivalent |
|---|---|---|---|
| `create_terminal_board` | `[path]`, `[focus]`, `[profile_id]` | Create a Terminal Board at an optional working directory. Run a command afterward with `run_terminal_command`. | `board terminal new` |
| `read_terminal_session` | `[board_id]`, `[profile_id]` | Read the visible Terminal Session buffer. | `terminal text` |
| `run_terminal_command` | `command`, `[board_id]`, `[profile_id]` | Send a shell command and press Enter in the target Terminal Session. The call does not wait for the command to finish; use `read_terminal_session` to inspect output. | `terminal run` |

## 5. Result and Error Contract

- Tool input schemas use JSON objects with `snake_case` property names. Required fields, allowed values, and defaults are stated in each tool description and schema.
- Each tool publishes an `outputSchema` matching its `structuredContent`. Successful calls also return concise text content. Board-targeted calls include `profile_id` and `board_id`; Board creation and Drawer placement include the created `board_id`.
- An IPC failure is returned with `isError: true` and a specific message. Invalid targets do not fall back to another Profile or Board.
- Read tools are annotated as read-only. Board removal, Drawer discard, and terminal command execution are annotated to describe their side effects. Annotations inform the MCP client; the client controls any approval UI.

Example `inspect_den` result:

```json
{
  "profiles": [{ "id": "3FA85F64-...", "name": "Default", "is_active": true, "has_window": true }],
  "profile": { "id": "3FA85F64-...", "name": "Default" },
  "profile_id": "3FA85F64-...",
  "desks": [{ "id": "93F4BD61-...", "label": "Main", "is_active": true, "board_count": 2 }],
  "active_desk": { "id": "93F4BD61-...", "label": "Main" },
  "boards": [{ "id": "4F72344C-...", "type": "web", "label": "Example", "url": "https://example.com", "is_focused": true }],
  "focused_board_id": "4F72344C-...",
  "drawer_item_count": 1
}
```

## 6. Deferred Tools

The first tool catalog focuses on common Den, Sheet, Drawer, and Terminal workflows. These CLI operations remain candidates for later MCP tools when a concrete use case calls for them:

- Arbitrary JavaScript evaluation (`sheet eval`).
- JavaScript-condition waits (`sheet wait --fn`).
- Low-level pointer events, drag, double-click, and focus.
- Screenshot capture.
- Raw Terminal input and process signaling (`terminal send`, `terminal kill`).
- Desk switching and creation, when those operations are available through the CLI.

## 7. Related decision

The MCP adoption and v1 direction in this specification are approved by [ADR 0055](adr/0055-add-den-mcp-server.md). ADR 0055 supersedes only ADR 0047's decision to avoid MCP; its CLI and IPC decisions remain in effect.
