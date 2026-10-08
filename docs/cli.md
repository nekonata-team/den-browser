# Den CLI (`den`) Specification

Den Browser provides a first-party command-line interface (`den`) bundled directly inside the application bundle at `Den Browser.app/Contents/MacOS/den`.

It enables AI coding agents (such as Codex and Claude Code) and human developers to inspect and control Den Browser from Terminal Boards or external shells with zero configuration.

---

## 1. Design Philosophy: `den <domain> <action>`

Den CLI groups resource operations by the kind of Board they act on:

```text
den <domain> <action> [arguments...] [options...]
```

`den health` is an application-level readiness check. It does not target a Desk or Board.

The command hierarchy follows the product model while keeping kind-specific operations under their Board:

```text
Den (Personal Environment for a Profile) ─── den
 ├── Profile (Isolated Browser Profile) ─── den profile <action>
 ├── Drawer (Unplaced Web Material) ─── den drawer <action>
 ├── Desk (Work Context) ─── den desk <action>
      └── Board (Work Surface) ─── den board <action>
           ├── Web Board ─── den board web <action>
           │    └── Sheet Stack
           ├── Inspection Board ─── den board inspection <action>
           └── Terminal Board ─── den board terminal <action>
                └── one Sheet backed by a Terminal Session
```

---

## 2. Common Options & Ambient Targeting

### Ambient Targeting
When `den` is executed from a shell inside a Terminal Board, Den Browser automatically injects:
- `DEN_BOARD_ID`: The immutable UUID of the calling Terminal Board.
- `DEN_PROFILE`: The UUID of the Profile owning the calling Terminal Board.
- `DEN_SOCKET`: The actual IPC domain socket path selected by Den Browser. It is `~/.den/den.sock` unless the app was started with a custom `DEN_SOCKET`.

These variables are attached when the Terminal Session is created and remain with that Session when its Board moves between Desks. A reattached zmx session keeps the shell environment from when the session was created. A Session is never given another Profile's context.

#### Profile Resolution
Target Profile resolution follows this strict priority:
1. **Explicit Profile ID**: Supplied via `--profile <uuid>`. If specified, it must be a valid UUID of an existing profile with an active window; invalid UUIDs, non-existent profiles, or profiles without an active window fail immediately (`exit 1`) with an explicit error and never fall back.
2. **Ambient Profile**: From `$DEN_PROFILE`. Follows the same strict validation as explicit profile ID.
3. **Ambient Board**: From `$DEN_BOARD_ID`. Locates the profile store containing that Board.
4. **Active Profile**: Fallback to the active window's profile (for external shells without profile scoping).

When a command is received with `DEN_BOARD_ID`:
1. Den Browser dynamically locates the Desk that currently contains that Terminal Board. Moving Boards across Desks does not break targeting because Desk membership is evaluated dynamically from live state.
2. Board-targeting commands resolve the appropriate Board on that Desk. Web commands scan for a Web Board; Terminal commands scan for a Terminal Board.

Board creation commands fall back to the active Desk when the ambient Board ID no longer exists, so a persistent Terminal session can still open a new Board after its original Board is removed.

For `den board web` operations on an existing Board, target Board resolution follows this priority:
1. **Explicit Board ID**: Supplied via `--board <id>`. If specified, the target must be a valid UUID for an existing Board; invalid or non-existent IDs fail immediately (`exit 1`) with an error and never fall back to ambient candidates.
2. **Adjacent Web Board**: Resolved relative to `callerBoardID` on its current Desk.
3. **Focused Board**: The currently focused Board on the active Desk, if it is a Web Board.
4. **First Web Board**: The first Web Board found on the active Desk.

For `den board terminal` operations on an existing Board, the caller's Terminal Board is preferred; otherwise the nearest Terminal Board is resolved relative to the caller on the current Desk.

### Global Options
- `--version`: Print the bundled Den Browser version and exit.
- `--json`: Force output as structured JSON. When standard output is redirected or piped (non-TTY), JSON output is enabled automatically.
- `--socket <path>`: Override the Unix domain socket path. Resolution order is explicit `--socket`, `$DEN_SOCKET`, then `~/.den/den.sock`.
- `--profile <uuid>`: Target specific Profile UUID (defaults to `$DEN_PROFILE` or ambient Profile). Fails immediately (`exit 1`) if invalid, not found, or has no active window.

### Board Targeting
- `--board <id>`: Explicitly target a specific Board by its UUID. Available on existing-Board operations under `den board web`, `den board terminal`, and `den board inspection read`, plus `den board close`; fails immediately if not found or invalid. Creation commands (`new`) do not accept `--board`.
- `den board close --board <id>` accepts any Board kind, including Inspection and Tutorial Boards. Web and Terminal Board commands require their corresponding Board kind.
- Inspection commands require an explicit Board ID. `den board inspection read --board <id>` requires an Inspection Board; it does not infer one from ambient focus or choose another Board.

### Direct IPC Requests
The bundled CLI communicates with Den Browser through newline-delimited Codable JSON on the Unix domain socket. Each `DenIPCRequest` contains one `DenIPCOperation` and caller context. Operations use typed `BoardTarget` and `DeskTarget` values to distinguish automatic resolution from an explicit UUID. Inspection operations and `openProfile` carry their required IDs directly. Snapshot capture is a distinct Sheet operation variant. `DenIPCResponse` carries a typed `DenIPCOperationResult` and the resolved target context; CLI JSON serializes the result's flat public projection and omits target metadata.

The app and bundled CLI must use matching versions and share these Swift types directly. This internal socket format has no legacy flat-JSON compatibility adapter. CLI arguments, MCP tool arguments, and public JSON responses remain specified separately in this document and [`mcp.md`](mcp.md).

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

### 3.2 `den board` (Board Surfaces & Layout)

Commands operating on Boards within the active Desk.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den board list` | `[-l]` | List all Boards on the active Desk with type (`web`/`inspection`/`terminal`/`tutorial`), label, and type-specific secondary information. JSON Inspection Board entries include their `target_board_id`. Use `-l` to include full Board IDs in human-readable output. | `den board list -l` |
| `den board focused` | `[-l]` | Show the currently focused Board on the active Desk. Use `-l` to include full Board ID in human-readable output. | `den board focused -l` |
| `den board close` | `[--board <id>]` | Close the specified Board or the target Web Board. Explicit IDs fail (`exit 1`) if invalid or not found. | `den board close --board 4F72344C-...` |

### 3.3 `den board web` (Web Board and Sheet Operations)
Commands operating on the Current Sheet of the resolved Web Board.

These commands operate on the Sheet Stack of a Web Board. Terminal Board interaction uses the `den board terminal` command family.

Every existing-Board Sheet operation accepts `--snapshot` to include a compact semantic snapshot after a successful operation. JSON retains the usual result fields and adds `snapshot`; TTY output prints the usual result followed by the snapshot. The snapshot comes from the same resolved Web Board, even if focus changes while the operation awaits. It does not wait for subsequent page activity: use a condition such as `den board web wait --text "Saved" --snapshot` when the observation depends on asynchronous completion. If the operation succeeds but snapshot capture fails, the response reports that distinction and exits with an error.

`den board web snapshot` already returns a snapshot, so `--snapshot` does not capture twice. Like other Sheet operations, `den board web interact` captures a final snapshot only when `--snapshot` is specified. `interact --full` requires `--snapshot`; `--no-snapshot` has been removed. On an action failure, `interact --snapshot` attempts a best-effort snapshot alongside failure metadata.

Compact snapshots retain visible semantic ancestors of interactive elements, such as menus, dialogs, navigation, and regions, so indentation identifies which area owns a control. Menus, dialogs, and listboxes also include a short contextual text line when available, without treating all descendant text as the area's name. Text controls include their current value (including an empty value), except password inputs; names, values, and contextual text are limited to 80 characters. `--full` retains these observations and includes other eligible visible semantic elements.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den board web new` | `<url> [--width <points>] [--focus]` | Open a **new** Web Board with a supported URL, bare hostname, or search query on the active Desk, start its Web runtime immediately, and return its UUID. `--width` sets its initial width in positive points; it may exceed the manual resize limit. Invalid or unsupported URL schemes fail. Use `den board web wait` to wait for loaded content. | `den board web new https://example.com --width 800` |
| `den board web navigate` | `<url>` | Navigate Current Sheet in the target Web Board to a supported URL, bare hostname, or search query. Invalid or unsupported URL schemes fail. | `den board web navigate https://example.com` |
| `den board web url` | None | Print Current Sheet URL of the target Web Board. | `den board web url` |
| `den board web reload` | None | Reload Current Sheet in the target Web Board. | `den board web reload` |
| `den board web eval` | `<script>` | Evaluate JavaScript and return the result. | `den board web eval document.title` |
| `den board web text` | None | Extract visible text content (`innerText`) from the sheet. | `den board web text` |
| `den board web back` | None | Navigate back in browsing history. | `den board web back` |
| `den board web forward` | None | Navigate forward in browsing history. | `den board web forward` |
| `den board web press` | `<key>` | Dispatch key events (`Enter`, `Escape`, `Tab`, arrows) to the active element. | `den board web press Enter` |
| `den board web scroll` | `[<direction-or-target>]` | Scroll the page (`down`, `up`, `top`, `bottom`, or pixel amount), or scroll a ref/selector into view. Defaults to `down`. | `den board web scroll @e2` |
| `den board web wait` | `[<target>] [--state <state>] [--url <glob>] [--text <text>] [--load <state>] [--fn <expression>] [--timeout <seconds>]` | Wait for one selector/ref state, URL glob, visible page text, load state (`domcontentloaded`, `load`, or `networkidle`), or JavaScript condition. Matching selectors use any visible element for `visible`, and succeed when all matches are hidden or absent for `hidden` and `detached`. The default timeout is 10 seconds. | `den board web wait --text "Saved"` |
| `den board web snapshot` | `[--full] [-i] [--within <target>]` | Extract the compact interactive semantic tree by default with short references (`@e1`, `@e2`) and control states such as `checked`, `unchecked`, `disabled`, `selected`, and `expanded`. `--full` includes all eligible visible semantic elements; `-i`/`--interactive` selects the default compact form explicitly; `--within` scopes either form to one selector or ref. | `den board web snapshot --within '[role=dialog]'` |
| `den board web query` | `<selector> [--visible] [--all] [--fields <list>]` | Return matching elements as structured JSON. Every result includes `ref` and `visible`; the default fields are `tag,role,name,text`. Use `value`, `checked`, `disabled`, `selected`, `expanded`, `class`, or `attr:<name>` for additional fields. `--visible` filters matches and `--all` returns every match instead of the first. | `den board web query "tr.zA" --visible --all --fields text,attr:data-email,class --json` |
| `den board web get` | `<text\|value\|attr\|count\|box> ...` | Read text, a form value, an attribute, the number of elements matching a selector, or bounding box (`x, y, width, height`). | `den board web get box @e1 --json` |
| `den board web is` | `<visible\|enabled\|checked> <target>` | Check one current boolean state for an element. | `den board web is checked @e3 --json` |
| `den board web click` | `[<target>] [--role <role> --name <name>] [--exact] [--new-board] [--focus]` | Click by ref/selector or by an accessible role and name. Semantic matching requires both `--role` and `--name`; `--exact` requires an exact name match. Use `--new-board` to open a clicked link in a new Web Board, returning `board_id`; add `--focus` to focus the new Board. | `den board web click @e1 --new-board --json` |
| `den board web dblclick` | `<target>` | Double-click an element by reference or selector. | `den board web dblclick @e1 --json` |
| `den board web focus` | `<target>` | Focus an element by reference or selector. | `den board web focus @e1 --json` |
| `den board web fill` | `<target> <value>` | Fill an input, textarea, or editable element with text by reference or selector. An empty value is valid. | `den board web fill @e2 "search query"` |
| `den board web type` | `[<target>] <text>` | Type text into an element by reference/selector or into the currently focused element (supports rich editors, Canvas, and contenteditable). | `den board web type @e2 "search query"` |
| `den board web drag` | `<source> [<target>] [--dx <dx>] [--dy <dy>] [--steps <steps>]` | Drag an element to another element or relative pixel offset (`--dx`, `--dy`). | `den board web drag @e1 --dx 100 --dy 50` |
| `den board web mouse` | `<move\|down\|up\|click\|wheel> ...` | Dispatch low-level pointer events (`move <x> <y>`, `down [btn]`, `up [btn]`, `click <x> <y> [--button <btn>] [--count <n>]`, `wheel <dy> [--dx <dx>]`). | `den board web mouse click 400 300 --json` |
| `den board web interact` | `[<script-or-file>] [--snapshot [--full]]` | Execute multiple sheet actions in order from a script, script file, or stdin (`-`). Actions follow standard `den board web` subcommand syntax (e.g. `click`, `dblclick`, `focus`, `fill`, `type`, `drag`, `mouse`, `wait`, `navigate`); execution stops at the first failure. JSON returns status and action metadata. Add `--snapshot` for a final semantic snapshot, and `--full` for the complete semantic tree. | `den board web interact "click @e1; fill @e2 'query'" --snapshot` |
| `den board web screenshot` | `[<path>]` | Save a PNG screenshot of the web sheet (defaults to temporary directory). | `den board web screenshot /tmp/screen.png` |

### 3.4 `den board terminal` (Terminal Board & Session Operations)

Commands operating on a Terminal Board and the Terminal Session it presents.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den board terminal new` | `[<path>] [--run <cmd>] [--width <points>] [--focus]` | Open a new Terminal Board, optionally running an initial command in an interactive shell. `--width` sets its initial width in positive points; it may exceed the manual resize limit. | `den board terminal new . --run "npm test" --width 800 --focus` |
| `den board terminal text` | `[--board <id>]` | Read visible terminal screen buffer as clean plain text. | `den board terminal text` |
| `den board terminal send` | `<text> [--board <id>]` | Inject raw text or escape sequences into the Terminal Session without executing it. | `den board terminal send "git status"` |
| `den board terminal run` | `<command> [--board <id>]` | Send a shell command and press Enter in the target Terminal Board. | `den board terminal run "git status"` |
| `den board terminal kill` | `[-s <signal>] [--board <id>]` | Send a POSIX signal to the foreground process group (defaults to `TERM`). | `den board terminal kill -s TERM` |

### 3.5 `den board inspection` (Inspection Boards & Context)

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den board inspection new` | `--target <web-board-id> [--focus]` | Create or reuse the Inspection Board associated with the specified Web Board and return its Board ID. The target must be an existing Web Board; the target relationship is preserved in the Board Group. Focus stays unchanged by default; use `--focus` to focus the Inspection Board. | `den board inspection new --target 4F72344C-... --json` |
| `den board inspection read` | `--board <inspection-board-id>` | Read the selected element and available page inspection context from the specified Inspection Board's target Web Board. This is read-only and requires an explicit Inspection Board ID. | `den board inspection read --board 4F72344C-... --json` |

The JSON result contains an `inspection` object describing the target page and current inspection data, including available selection details, accessible labels, a captured CSS selector, capture time, document identity, ancestor path, retained console or JavaScript events, and dropped-event count. A page with no selected element is reported as unselected. For current `@e…` references, use `den board web snapshot` or `den board web query` on the target Web Board. Exact optional fields depend on available page data; see [Inspection](inspection.md).

### 3.6 `den desk` (Desks)

Commands operating on Desks within the Den.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den desk list` | None | List all Desks in the Den with ID, label, board count, and active status. | `den desk list` |

### 3.7 `den drawer` (Drawer & Web Material)

Commands operating on the Den-wide Drawer for web material whose Desk context is not yet settled.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den drawer list` | None | List all Drawer Items in the Drawer with ID, title, and URL. | `den drawer list` |
| `den drawer keep` | `<url> [--title <text>]` | Keep a supported URL or bare hostname in the Drawer as a Drawer Item without changing Desk layout. Search queries and invalid or unsupported URL schemes fail. | `den drawer keep https://example.com` |
| `den drawer place` | `<id>` | Place a Drawer Item onto the active Desk as a Web Board, start its Web runtime immediately, and remove the item from the Drawer. | `den drawer place 4F72344C-...` |
| `den drawer discard` | `<id>` | Discard a Drawer Item without placing it onto a Desk. | `den drawer discard 4F72344C-...` |

Web URL inputs use the same resolution policy across these commands. Explicit `http://`, `https://`, and absolute local `file://` URLs are accepted; a bare hostname such as `example.com` or `localhost:3000` is completed with `https://`. `den board web navigate` and `den board web new` also accept search queries, using the configured Search Engine. `den drawer keep` accepts only URL input, so search queries and unsupported schemes such as `ftp://` or `mailto:` fail before any state change. Accepted URLs are canonicalized after validation.

### 3.8 `den profile` (Profiles)

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
$ den board web url
https://example.com/docs
```

### Non-TTY / `--json` Output (Agent & `jq` Mode)
When piped or when `--json` is supplied, `den` outputs single-line JSON on standard output with standard Unix exit codes. Properties are flat and use `snake_case` for direct 1-level `jq` access:

**Board Creation (`board web new`, `board terminal new`, `board inspection new`)**:
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
Web Boards include `url`; Zellij and zmx Terminal Boards include `session_name` when a named session is attached. Inspection Boards identify their target with `target_board_id`. `is_focused` indicates whether the Board is currently focused on the Desk.

**Board Focused (`board focused`)**:
```json
{"board":{"id":"4F72344C-...","is_focused":true,"label":"Example","type":"web","url":"https://example.com"},"board_id":"4F72344C-...","ok":true}
```
```bash
BOARD_ID=$(den board focused | jq -r .board_id)
```

**Terminal Screen Buffer (`board terminal text`)**:
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

Query fields that are unavailable on an element are omitted. `attributes` contains requested `class` or `attr:<name>` values that exist on the element. The `value` response can be an empty string. Snapshots include compact text-control values except password inputs; use `get value` when the complete value is needed.

Element names use labels and visible content rather than form values, except for input buttons whose value is their caption. Native disabled state, including inheritance from a disabled fieldset, takes precedence over `aria-disabled="false"`. URL globs match literal segments in order without overlap; `*` matches zero or more characters.

**Actions (`click`, `dblclick`, `focus`, `fill`, `type`, `drag`, `mouse`, `press`, `scroll`, `navigate`, `place`, `discard`, `send`)**:
```json
{"message":"Clicked @e1","ok":true}
```

**Click in New Board (`board web click --new-board`)**:
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
