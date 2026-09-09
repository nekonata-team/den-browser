# Den CLI (`den`) Specification

Den Browser provides a first-party command-line interface (`den`) bundled directly inside the application bundle at `Den Browser.app/Contents/MacOS/den`.

It enables AI coding agents (such as Codex and Claude Code) and human developers to inspect and control Den Browser from Terminal Boards or external shells with zero configuration.

---

## 1. Design Philosophy: `den <domain> <action>`

Den CLI follows a strict resource-oriented pattern:

```text
den <domain> <action> [arguments...] [options...]
```

Each `<domain>` corresponds directly to a core domain entity defined in [CONTEXT.md](../CONTEXT.md) and reflects the directory structure in `Den Browser/Features/Den/`:

```text
Den (Application Workspace) ─── den
 ├── Drawer (Temporary Web Material) ─── den drawer <action>
 ├── Desk (Virtual Workspace) ─── den desk <action>
      └── Board (Work Surface) ─── den board <action>
           ├── [Web] Sheet (Web Screen) ─── den sheet <action>
           └── [Terminal] Session ─── den terminal <action>
```

---

## 2. Common Options & Ambient Targeting

### Ambient Targeting
When `den` is executed from a shell inside a Terminal Board, Den Browser automatically injects:
- `DEN_BOARD_ID`: The immutable UUID of the calling Terminal Board.
- `DEN_SOCKET`: The path to the IPC domain socket (defaults to `~/.den/den.sock`).

When a command is received with `DEN_BOARD_ID`:
1. Den Browser dynamically locates the Desk that currently contains that Terminal Board. Moving Boards across Desks does not break targeting because Desk membership is evaluated dynamically from live state.
2. The nearest adjacent Web Board on that Desk is resolved (scanned rightward, then leftward).

For `sheet` commands, target Web Board resolution follows this priority:
1. **Explicit Board ID**: Supplied via `--board <id>`. If specified, the target must be a valid UUID for an existing Board; invalid or non-existent IDs fail immediately (`exit 1`) with an error and never fall back to ambient candidates.
2. **Adjacent Web Board**: Resolved relative to `callerBoardID` on its current Desk.
3. **Focused Board**: The currently focused Board on the active Desk, if it is a Web Board.
4. **First Web Board**: The first Web Board found on the active Desk.

### Global Options
- `--json`: Force output as structured JSON. When standard output is redirected or piped (non-TTY), JSON output is enabled automatically.
- `--board <id>`: Explicitly target a specific Board by its UUID. Fails immediately if not found or invalid.
- `--socket <path>`: Override the Unix domain socket path (defaults to `~/.den/den.sock` or `$DEN_SOCKET`).

---

## 3. Command Specification (v1)

### 3.1 `den sheet` (Web Screen & Content)
Commands operating on the Current Sheet of the resolved Web Board.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den sheet open` | `<url>` | Navigate the current sheet to `<url>`. | `den sheet open https://example.com` |
| `den sheet url` | None | Print the current URL of the sheet. | `den sheet url` |
| `den sheet reload` | None | Reload the current sheet. | `den sheet reload` |
| `den sheet eval` | `<script>` | Evaluate JavaScript and return the result. | `den sheet eval document.title` |
| `den sheet text` | None | Extract visible text content (`innerText`) from the sheet. | `den sheet text` |
| `den sheet back` | None | Navigate back in browsing history. | `den sheet back` |
| `den sheet forward` | None | Navigate forward in browsing history. | `den sheet forward` |
| `den sheet press` | `<key>` | Dispatch key events (`Enter`, `Escape`, `Tab`, arrows) to the active element. | `den sheet press Enter` |
| `den sheet scroll` | `[<direction>]` | Scroll the page (`down`, `up`, `top`, `bottom`, or pixel amount). Defaults to `down`. | `den sheet scroll down` |
| `den sheet wait` | `<target>` | Wait for a duration in seconds (`2`, `0.5`) or until a selector/ref appears. | `den sheet wait "#results"` |
| `den sheet snapshot` | `[-i]` | Extract semantic DOM tree with short references (`@e1`, `@e2`). `-i` filters to interactive elements only. | `den sheet snapshot -i` |
| `den sheet click` | `<target>` | Click an element by reference (`@e1`) or CSS selector. | `den sheet click @e1` |
| `den sheet fill` | `<target> <value>` | Fill an input/textarea with text by reference or selector. | `den sheet fill @e2 "search query"` |
| `den sheet screenshot` | `[<path>]` | Save a PNG screenshot of the web sheet (defaults to temporary directory). | `den sheet screenshot /tmp/screen.png` |

### 3.2 `den board` (Board Surfaces & Layout)
Commands operating on Boards within the active Desk.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den board list` | None | List all Boards on the active Desk with ID, type (`web`/`terminal`), and label. | `den board list` |
| `den board new` | `<url> [--focus]` | Open a **new** Web Board with `<url>` on the active Desk (does not steal focus unless `--focus` is given) and return its UUID. | `den board new https://example.com` |
| `den board close` | `[<id>]` | Close the specified Board or the target Web Board. Closing by explicit `<id>` fails (`exit 1`) without closing the active Board if the ID is invalid or not found. | `den board close` |

### 3.3 `den desk` (Desks & Workspaces)
Commands operating on Desks within the Den.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den desk list` | None | List all Desks in the Den with ID, label, board count, and active status. | `den desk list` |

### 3.4 `den drawer` (Drawer & Web Material)
Commands operating on the Den-wide Drawer for web material whose Desk context is not yet settled.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den drawer list` | None | List all items in the Drawer with ID, title, and URL. | `den drawer list` |
| `den drawer keep` | `<url> [--title <text>]` | Keep a URL in the Drawer as a Drawer Item without changing Desk layout. | `den drawer keep https://example.com` |
| `den drawer place` | `<id>` | Place a Drawer Item onto the active Desk as a Web Board (item leaves Drawer). | `den drawer place 4F72344C-...` |
| `den drawer discard` | `<id>` | Discard a Drawer Item without placing it onto a Desk. | `den drawer discard 4F72344C-...` |

### 3.5 `den terminal` (Terminal Boards)
Commands operating on native Terminal Boards.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den terminal list` | None | List Terminal Boards on active Desk with ID, label, working directory, and foreground PID. | `den terminal list` |
| `den terminal new` | `[<path>] [--run <cmd>] [--focus]` | Spawn a Terminal Board, optionally running an initial command in an interactive shell. | `den terminal new . --run "npm test" --focus` |
| `den terminal text` | `[--board <id>]` | Read visible terminal screen buffer as clean plain text. | `den terminal text` |
| `den terminal send` | `<text> [--board <id>]` | Inject raw text or escape sequences into terminal pty. | `den terminal send "git status\n"` |
| `den terminal kill` | `[-s <signal>] [--board <id>]` | Send a POSIX signal to the foreground process group (defaults to `TERM`). | `den terminal kill -s TERM` |

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

**Board Creation (`board new`, `terminal new`)**:
```json
{"ok":true,"board_id":"4F72344C-F4E3-438D-99CB-2F12A79F0004"}
```
```bash
BOARD_ID=$(den board new https://example.com | jq -r .board_id)
```

**Board Listing (`board list`)**:
```json
{"ok":true,"boards":[{"id":"4F72344C-...","label":"Example","type":"web","url":"https://example.com"}]}
```
```bash
den board list | jq -r '.boards[] | select(.type == "web") | .id'
```

**Terminal Listing (`terminal list`)**:
```json
{"ok":true,"terminals":[{"foreground_pid":87498,"id":"C40D049C-...","label":"main","working_directory":"/Users/hiroaki/Documents/main"}]}
```
```bash
den terminal list | jq -r '.terminals[] | .id'
```

**Terminal Screen Buffer (`terminal text`)**:
```json
{"ok":true,"text":"$ npm test\nPASS ..."}
```

**Desk Listing (`desk list`)**:
```json
{"ok":true,"desks":[{"board_count":2,"id":"93F4BD61-...","is_active":true,"label":"Main"}]}
```

**Drawer Items (`drawer list`)**:
```json
{"drawer_items":[{"id":"4F72344C-...","title":"Example Docs","url":"https://example.com"}],"ok":true}
```

**Drawer Item Keep (`drawer keep`)**:
```json
{"drawer_item_id":"4F72344C-...","message":"Kept in Drawer: https://example.com","ok":true}
```

**Sheet URL / Snapshot / Value**:
```json
{"ok":true,"url":"https://example.com/docs"}
{"ok":true,"snapshot":"@e1 [a] \"Learn more\"\n@e2 [button] \"Submit\""}
{"ok":true,"value":"42"}
```

**Actions (`click`, `fill`, `press`, `scroll`, `wait`, `open`, `place`, `discard`, `send`)**:
```json
{"message":"Clicked @e1","ok":true}
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

This equips the agent with the procedural knowledge in `.agents/skills/den/SKILL.md` to autonomously reason over web elements using the Snapshot + Ref model, navigate history, and control Web Boards.

---

## 6. Future Roadmap

- **`den board`**:
  - `den board focus <id>`
- **`den desk`**:
  - `den desk switch <id|label>`
  - `den desk new [<label>]`
