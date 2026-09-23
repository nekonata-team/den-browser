# Den MCP Server (`den mcp`) Specification

**Status: Approved for implementation**

Den Browser exposes its common operations as MCP tools so MCP clients can present them to models with descriptions and typed arguments. This is a second interface to Den operations, alongside the first-party [`den` CLI](cli.md).

## 1. Rationale and Design Philosophy

### Why Reconsider MCP Now

[ADR 0047](adr/0047-integrate-den-cli.md) avoided MCP when the CLI's operational surface was intentionally small. The CLI now covers common Den, Sheet, Drawer, and Terminal operations over typed IPC, so MCP can reuse existing behavior instead of adding a second browser-automation stack.

MCP adds a distinct benefit: compatible clients can discover Den tools with descriptions and JSON Schemas, then call them without learning CLI syntax or parsing shell output. The current stateless MCP core also makes a sessionless Streamable HTTP server practical when remote transport is needed. It does not remove Den's own live Profile, Board, Sheet, or Terminal state; those remain owned by Den Browser.

Version 1 remains a local stdio server because the MCP client can launch the bundled `den` executable directly. Stdio still has one child process per client. Den MCP itself keeps no client-specific target state: each tool call carries optional `profile_id` and `board_id` arguments or resolves them using the CLI's documented defaults. The [2026-07-28 MCP specification](https://blog.modelcontextprotocol.io/posts/2026-07-28/) removes protocol-level sessions from Streamable HTTP; it does not change stdio's process lifetime.

### Action-First Tools

The CLI groups commands by domain:

```text
den <domain> <action>
```

MCP tools are presented as a flat catalog, so tool names lead with the action and identify its object:

```text
inspect_den
open_sheet
click_sheet_element
save_url_to_drawer
```

Tool arguments are JSON objects described by JSON Schema. They are not CLI argument strings, and tools do not accept a generic command to execute. An MCP tool may combine related CLI reads when one result gives the model better context; `inspect_den` is the primary example.

MCP tools reuse Den's existing operation semantics, URL rules, and typed IPC. They do not create a second set of Den behavior. Product terms follow [CONTEXT.md](../CONTEXT.md): Den, Desk, Board, Sheet, and Terminal Session.

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

MCP clients discover tools with their descriptions and `inputSchema`. A call supplies a tool name and an `arguments` object matching that schema:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "open_sheet",
    "arguments": {
      "url": "https://example.com",
      "board_id": "4F72344C-F4E3-438D-99CB-2F12A79F0004"
    }
  }
}
```

`tools/call` carries that object in the MCP request. Missing, unknown, or invalid values fail before a side effect.

For example, `open_sheet` advertises an object schema with a required URL and optional targets:

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
| `profile_id` | UUID string, optional | Target Profile. A tool argument overrides the server's `--profile`; otherwise resolution follows `--profile`, `$DEN_PROFILE`, ambient Board's Profile, then the active Profile. An explicit invalid, missing, or windowless Profile fails without fallback. |
| `board_id` | UUID string, optional | Target a specific Board for Sheet and Terminal Session tools. An explicit invalid or non-existent Board fails without fallback. If omitted, Sheet tools use the CLI's ambient, adjacent, focused, then first-Web-Board resolution; Terminal tools prefer the ambient Terminal Board, then the nearest Terminal Board. |

After `inspect_den` or `inspect_sheet`, clients should pass the returned `profile_id` and `board_id` to subsequent calls when a workflow must stay on that target. A successful Board-targeted call returns its effective `profile_id` and `board_id` so the model can keep later calls anchored if focus changes.

For `click_sheet_element`, provide either `target` or both `role` and `name`; `role` and `name` must be used together. `focus_new_board` requires `open_in_new_board`. For `read_sheet_element`, `field` is `text`, `value`, `attribute`, `count`, or `box`; `attribute` is required for the `attribute` field. For `wait_for_sheet`, provide exactly one condition: `target` with an optional `state`, `url`, `text`, or `load_state`. Selector states are `attached`, `visible`, `hidden`, or `detached`; load states follow [`cli.md`](cli.md).

`query_sheet.fields` accepts `tag`, `role`, `name`, `text`, `value`, `checked`, `disabled`, `selected`, `expanded`, `class`, and `attr:<name>`. `read_sheet_state.state` is `visible`, `enabled`, or `checked`. For `scroll_sheet`, provide `direction` (`down`, `up`, `top`, or `bottom`) or `target` (a ref or selector); they are mutually exclusive and the default direction is `down`.

`open_profile` changes the active Profile Window but does not change the server's launch options. Pass `profile_id` on later calls when they must stay scoped to that Profile.

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

## 7. Decision Status

The MCP adoption and v1 direction in this specification are approved by [ADR 0055](adr/0055-add-den-mcp-server.md). ADR 0055 supersedes only ADR 0047's decision to avoid MCP; its CLI and IPC decisions remain in effect.
