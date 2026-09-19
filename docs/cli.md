# Den CLI (`den`) Specification

Den Browser provides a first-party command-line interface (`den`) bundled directly inside the application bundle at `Den Browser.app/Contents/MacOS/den`.

It enables AI coding agents (such as Codex and Claude Code) and human developers to inspect and control Den Browser from Terminal Boards or external shells with zero configuration.

---

## 1. Design Philosophy: `den <domain> <action>`

Den CLI follows a strict resource-oriented pattern:

```text
den <domain> <action> [arguments...] [options...]
```

`den health` is an application-level readiness check. It does not target a Desk or Board.

Each `<domain>` corresponds directly to a core domain entity defined in [CONTEXT.md](../CONTEXT.md) and reflects the directory structure in `Den Browser/Features/Den/`:

```text
Den (Application Workspace) ─── den
 ├── Profile (Isolated Browser Profile) ─── den profile <action>
 ├── Drawer (Temporary Web Material) ─── den drawer <action>
 ├── Desk (Virtual Workspace) ─── den desk <action>
      └── Board (Work Surface) ─── den board <action>
           ├── Web Board ─── den board web <action>
           │    └── Sheet (Web Screen) ─── den sheet <action>
           └── Terminal Board ─── den board terminal <action>
                └── Terminal Session ─── den terminal <action>
```

---

## 2. Common Options & Ambient Targeting

### Ambient Targeting
When `den` is executed from a shell inside a Terminal Board, Den Browser automatically injects:
- `DEN_BOARD_ID`: The immutable UUID of the calling Terminal Board.
- `DEN_PROFILE`: The UUID of the Profile owning the calling Terminal Board.
- `DEN_SOCKET`: The path to the IPC domain socket (defaults to `~/.den/den.sock`).

#### Profile Resolution
Target Profile resolution follows this strict priority:
1. **Explicit Profile ID**: Supplied via `--profile <uuid>`. If specified, it must be a valid UUID of an existing profile with an active window; invalid UUIDs, non-existent profiles, or profiles without an active window fail immediately (`exit 1`) with an explicit error and never fall back.
2. **Ambient Profile**: From `$DEN_PROFILE`. Follows the same strict validation as explicit profile ID.
3. **Ambient Board**: From `$DEN_BOARD_ID`. Locates the profile store containing that Board.
4. **Active Profile**: Fallback to the active window's profile (for external shells without profile scoping).

When a command is received with `DEN_BOARD_ID`:
1. Den Browser dynamically locates the Desk that currently contains that Terminal Board. Moving Boards across Desks does not break targeting because Desk membership is evaluated dynamically from live state.
2. Board-targeting commands resolve the appropriate Board on that Desk. Web commands scan for a Web Board; Terminal commands scan for a Terminal Board.

For `sheet` commands, target Web Board resolution follows this priority:
1. **Explicit Board ID**: Supplied via `--board <id>`. If specified, the target must be a valid UUID for an existing Board; invalid or non-existent IDs fail immediately (`exit 1`) with an error and never fall back to ambient candidates.
2. **Adjacent Web Board**: Resolved relative to `callerBoardID` on its current Desk.
3. **Focused Board**: The currently focused Board on the active Desk, if it is a Web Board.
4. **First Web Board**: The first Web Board found on the active Desk.

For `terminal` commands, the caller's Terminal Board is preferred; otherwise the nearest Terminal Board is resolved relative to the caller on the current Desk.

### Global Options
- `--json`: Force output as structured JSON. When standard output is redirected or piped (non-TTY), JSON output is enabled automatically.
- `--socket <path>`: Override the Unix domain socket path (defaults to `~/.den/den.sock` or `$DEN_SOCKET`).
- `--profile <uuid>`: Target specific Profile UUID (defaults to `$DEN_PROFILE` or ambient Profile). Fails immediately (`exit 1`) if invalid, not found, or has no active window.

### Board Targeting
- `--board <id>`: Explicitly target a specific Board by its UUID. Available on `den sheet`, `den terminal`, and `den board close`; fails immediately if not found or invalid.

### Direct IPC Requests
The CLI communicates with Den Browser through a newline-delimited JSON request on the Unix domain socket. A request contains the `command`, optional target IDs, and an optional typed `payload` whose shape is determined by the command.

- Value-bearing commands such as `sheet click`, `sheet wait`, `sheet get`, and `terminal send` put positional values and flags in `payload`; the server does not re-parse command-line strings.
- Commands without values omit `payload`.
- The payload command must match the top-level `command`. Missing, unknown, or invalid payload values fail before a side effect.
- The legacy `args` request field is rejected. Direct socket clients must migrate to the typed payload schema; there is no positional-argument fallback.
- `sheet interact` sends one `sheet.interact` payload containing typed steps. Each step retains its source line and text for failure reporting, plus the typed command payload used for execution.

---

## 3. Command Specification (v1)

### 3.1 `den health` (Den Readiness)

Checks whether Den Browser is accepting IPC requests.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den health` | None | Check whether Den Browser is ready. | `den health` |

On a TTY, it prints `healthy`. With `--json` or when piped, it returns:

```json
{"ok":true}
```

### 3.2 `den sheet` (Web Screen & Content)
Commands operating on the Current Sheet of the resolved Web Board.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den sheet open` | `<url>` | Navigate Current Sheet in the target Web Board to `<url>` or a search query. | `den sheet open https://example.com` |
| `den sheet url` | None | Print Current Sheet URL of the target Web Board. | `den sheet url` |
| `den sheet reload` | None | Reload Current Sheet in the target Web Board. | `den sheet reload` |
| `den sheet eval` | `<script>` | Evaluate JavaScript and return the result. | `den sheet eval document.title` |
| `den sheet text` | None | Extract visible text content (`innerText`) from the sheet. | `den sheet text` |
| `den sheet back` | None | Navigate back in browsing history. | `den sheet back` |
| `den sheet forward` | None | Navigate forward in browsing history. | `den sheet forward` |
| `den sheet press` | `<key>` | Dispatch key events (`Enter`, `Escape`, `Tab`, arrows) to the active element. | `den sheet press Enter` |
| `den sheet scroll` | `[<direction-or-target>]` | Scroll the page (`down`, `up`, `top`, `bottom`, or pixel amount), or scroll a ref/selector into view. Defaults to `down`. | `den sheet scroll @e2` |
| `den sheet wait` | `[<target>] [--state <state>] [--url <glob>] [--text <text>] [--load <state>] [--fn <expression>] [--timeout <seconds>]` | Wait for one selector/ref state, URL glob, visible page text, load state (`domcontentloaded`, `load`, or `networkidle`), or JavaScript condition. Matching selectors use any visible element for `visible`, and succeed when all matches are hidden or absent for `hidden` and `detached`. The default timeout is 10 seconds. | `den sheet wait --text "Saved"` |
| `den sheet snapshot` | `[--full] [-i] [--within <target>]` | Extract the compact interactive semantic tree by default with short references (`@e1`, `@e2`) and control states such as `checked`, `unchecked`, `disabled`, `selected`, and `expanded`. `--full` includes all eligible visible semantic elements; `-i`/`--interactive` selects the default compact form explicitly; `--within` scopes either form to one selector or ref. | `den sheet snapshot --within '[role=dialog]'` |
| `den sheet query` | `<selector> [--visible] [--all] [--fields <list>]` | Return matching elements as structured JSON. Every result includes `ref` and `visible`; the default fields are `tag,role,name,text`. Use `value`, `checked`, `disabled`, `selected`, `expanded`, `class`, or `attr:<name>` for additional fields. `--visible` filters matches and `--all` returns every match instead of the first. | `den sheet query "tr.zA" --visible --all --fields text,attr:data-email,class --json` |
| `den sheet get` | `<text\|value\|attr\|count\|box> ...` | Read text, a form value, an attribute, the number of elements matching a selector, or bounding box (`x, y, width, height`). | `den sheet get box @e1 --json` |
| `den sheet is` | `<visible\|enabled\|checked> <target>` | Check one current boolean state for an element. | `den sheet is checked @e3 --json` |
| `den sheet click` | `[<target>] [--role <role> --name <name>] [--exact] [--new-board] [--focus]` | Click by ref/selector or by an accessible role and name. Semantic matching requires both `--role` and `--name`; `--exact` requires an exact name match. Use `--new-board` to open a clicked link in a new Web Board, returning `board_id`; add `--focus` to focus the new Board. | `den sheet click @e1 --new-board --json` |
| `den sheet dblclick` | `<target>` | Double-click an element by reference or selector. | `den sheet dblclick @e1 --json` |
| `den sheet focus` | `<target>` | Focus an element by reference or selector. | `den sheet focus @e1 --json` |
| `den sheet fill` | `<target> <value>` | Fill an input, textarea, or editable element with text by reference or selector. An empty value is valid. | `den sheet fill @e2 "search query"` |
| `den sheet type` | `[<target>] <text>` | Type text into an element by reference/selector or into the currently focused element (supports rich editors, Canvas, and contenteditable). | `den sheet type @e2 "search query"` |
| `den sheet drag` | `<source> [<target>] [--dx <dx>] [--dy <dy>] [--steps <steps>]` | Drag an element to another element or relative pixel offset (`--dx`, `--dy`). | `den sheet drag @e1 --dx 100 --dy 50` |
| `den sheet mouse` | `<move\|down\|up\|click\|wheel> ...` | Dispatch low-level pointer events (`move <x> <y>`, `down [btn]`, `up [btn]`, `click <x> <y> [--button <btn>] [--count <n>]`, `wheel <dy> [--dx <dx>]`). | `den sheet mouse click 400 300 --json` |
| `den sheet interact` | `[<script-or-file>] [--full]` | Execute multiple sheet actions in order from a script, script file, or stdin (`-`) and return a final semantic snapshot. Actions follow standard `den sheet` subcommand syntax (e.g. `click`, `dblclick`, `focus`, `fill`, `type`, `drag`, `mouse`, `wait`); execution stops at the first failure. Use `--full` for the complete semantic tree. | `den sheet interact "click @e1; fill @e2 'query'"` |
| `den sheet screenshot` | `[<path>]` | Save a PNG screenshot of the web sheet (defaults to temporary directory). | `den sheet screenshot /tmp/screen.png` |

### 3.3 `den board` (Board Surfaces & Layout)
Commands operating on Boards within the active Desk.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den board list` | `[-l]` | List all Boards on the active Desk with type (`web`/`terminal`), label, and type-specific secondary information. Use `-l` to include full Board IDs in human-readable output. | `den board list -l` |
| `den board focused` | `[-l]` | Show the currently focused Board on the active Desk. Use `-l` to include full Board ID in human-readable output. | `den board focused -l` |
| `den board close` | `[--board <id>]` | Close the specified Board or the target Web Board. Explicit IDs fail (`exit 1`) if invalid or not found. | `den board close --board 4F72344C-...` |

### 3.4 `den board web` (Web Boards)

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den board web new` | `<url> [--focus]` | Open a **new** Web Board with `<url>` on the active Desk, start its Web runtime immediately, and return its UUID. Use `den sheet wait` to wait for loaded content. | `den board web new https://example.com` |

### 3.5 `den board terminal` (Terminal Boards)

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den board terminal new` | `[<path>] [--run <cmd>] [--focus]` | Open a new Terminal Board, optionally running an initial command in an interactive shell. | `den board terminal new . --run "npm test" --focus` |

### 3.6 `den desk` (Desks & Workspaces)
Commands operating on Desks within the Den.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den desk list` | None | List all Desks in the Den with ID, label, board count, and active status. | `den desk list` |

### 3.7 `den drawer` (Drawer & Web Material)
Commands operating on the Den-wide Drawer for web material whose Desk context is not yet settled.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den drawer list` | None | List all Drawer Items in the Drawer with ID, title, and URL. | `den drawer list` |
| `den drawer keep` | `<url> [--title <text>]` | Keep a URL in the Drawer as a Drawer Item without changing Desk layout. | `den drawer keep https://example.com` |
| `den drawer place` | `<id>` | Place a Drawer Item onto the active Desk as a Web Board, start its Web runtime immediately, and remove the item from the Drawer. | `den drawer place 4F72344C-...` |
| `den drawer discard` | `<id>` | Discard a Drawer Item without placing it onto a Desk. | `den drawer discard 4F72344C-...` |

### 3.8 `den terminal` (Terminal Sessions)
Commands operating on Terminal Sessions in the target Terminal Board.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den terminal text` | `[--board <id>]` | Read visible terminal screen buffer as clean plain text. | `den terminal text` |
| `den terminal send` | `<text> [--board <id>]` | Inject raw text or escape sequences into the Terminal Session without executing it. | `den terminal send "git status"` |
| `den terminal run` | `<command> [--board <id>]` | Send a shell command and press Enter in the target Terminal Board. | `den terminal run "git status"` |
| `den terminal kill` | `[-s <signal>] [--board <id>]` | Send a POSIX signal to the foreground process group (defaults to `TERM`). | `den terminal kill -s TERM` |

### 3.9 `den profile` (Profiles)
Commands inspecting and managing profiles in Den Browser.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den profile list` | None | List all profiles with name, UUID, active status, and open window status. | `den profile list` |
| `den profile open` | `<uuid>` | Open a window for the specified profile, or activate it if already open. | `den profile open 3FA85F64-...` |

---

## 4. Output Contract (Dual Human + Agent Ergonomics)

### TTY Output (Human Mode)
When connected to an interactive terminal, `den` prints readable plain text and writes error messages to `stderr`.

```text
$ den sheet url
https://example.com/docs
```

### Non-TTY / `--json` Output (Agent & `jq` Mode)
When piped or when `--json` is supplied, `den` outputs single-line JSON on standard output with standard Unix exit codes. Properties are flat and use `snake_case` for direct 1-level `jq` access:

**Board Creation (`board web new`, `board terminal new`)**:
```json
{"ok":true,"board_id":"4F72344C-F4E3-438D-99CB-2F12A79F0004"}
```
```bash
BOARD_ID=$(den board web new https://example.com | jq -r .board_id)
```

**Board Listing (`board list`)**:
```json
{"ok":true,"boards":[{"id":"4F72344C-...","is_focused":true,"label":"Example","type":"web","url":"https://example.com"}]}
```
```bash
den board list | jq -r '.boards[] | select(.type == "web") | .id'
```
Web Boards include `url`; Zellij and zmx Terminal Boards include `session_name` when a named session is attached. `is_focused` indicates whether the Board is currently focused on the Desk.

**Board Focused (`board focused`)**:
```json
{"board":{"id":"4F72344C-...","is_focused":true,"label":"Example","type":"web","url":"https://example.com"},"board_id":"4F72344C-...","ok":true}
```
```bash
BOARD_ID=$(den board focused | jq -r .board_id)
```

**Terminal Screen Buffer (`terminal text`)**:
```json
{"ok":true,"text":"$ npm test\nPASS ..."}
```

**Desk Listing (`desk list`)**:
```json
{"ok":true,"desks":[{"board_count":2,"id":"93F4BD61-...","is_active":true,"label":"Main"}]}
```

**Profile Listing (`profile list`)**:
```json
{"ok":true,"profiles":[{"has_window":true,"id":"3FA85F64-...","is_active":true,"name":"Default"}]}
```

**Drawer Items (`drawer list`)**:
```json
{"drawer_items":[{"id":"4F72344C-...","title":"Example Docs","url":"https://example.com"}],"ok":true}
```

**Drawer Item Keep (`drawer keep`)**:
```json
{"drawer_item_id":"4F72344C-...","message":"Kept in Drawer: https://example.com","ok":true}
```

**Sheet URL / Text / Snapshot / Query / Get / Is**:
```json
{"ok":true,"url":"https://example.com/docs"}
{"ok":true,"text":"Visible text from the element"}
{"ok":true,"snapshot":"@e1 [button] \"Submit\""}
{"ok":true,"elements":[{"ref":"@e1","tag":"button","role":"option","name":"GitHub","text":"GitHub","visible":true,"attributes":{"class":"choice","data-email":"github@example.com"}}]}
{"ok":true,"attribute":"github@example.com"}
{"ok":true,"count":12}
{"ok":true,"value":"42"}
{"ok":true,"checked":true}
{"ok":true,"visible":false}
{"ok":true,"enabled":true}
{"ok":true,"box":{"height":40,"width":120,"x":10,"y":20}}
```

Query fields that are unavailable on an element are omitted. `attributes` contains requested `class` or `attr:<name>` values that exist on the element. The `value` response can be an empty string. Snapshot omits form values; use `get value` when a value is needed.

Element names use labels and visible content rather than form values, except for input buttons whose value is their caption. Native disabled state, including inheritance from a disabled fieldset, takes precedence over `aria-disabled="false"`. URL globs match literal segments in order without overlap; `*` matches zero or more characters.

**Actions (`click`, `dblclick`, `focus`, `fill`, `type`, `drag`, `mouse`, `press`, `scroll`, `wait`, `open`, `place`, `discard`, `send`)**:
```json
{"message":"Clicked @e1","ok":true}
```

**Click in New Board (`sheet click --new-board`)**:
```json
{"board_id":"8E192A0B-...","message":"Opened @e1 in new Board","ok":true,"url":"https://example.com/docs"}
```

**Failure (`exit 1`)**:
```json
{"error":"Element not found: @e1","ok":false}
```

---

## 5. Agent Skill Integration (`skills.sh`)

Autonomous coding agents (such as Claude Code, Cursor, Antigravity, Windsurf) can install the official Den Browser agent skill directly from GitHub via `npx skills`:

```bash
# Install to the current project (default)
npx skills add nekonata-team/den-browser --skill den

# Install to the user-level agent environment
npx skills add nekonata-team/den-browser --skill den --global
```

This equips the agent with the procedural knowledge in `.agents/skills/den/SKILL.md` to autonomously reason over web elements using the Snapshot + Ref model, navigate history, and control Web Boards. The skill resolves `den` from `PATH` (linked automatically when installed via Homebrew Cask) or falls back to `/Applications/Den Browser.app/Contents/MacOS/den`.

---

## 6. Future Roadmap

- **`den board`**:
  - `den board focus <id>`
- **`den desk`**:
  - `den desk switch <id|label>`
  - `den desk new [<label>]`
- **`den profile`**:
  - `den profile close <uuid>`
