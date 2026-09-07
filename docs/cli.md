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
 ├── Desk (Virtual Workspace) ─── den desk <action>
      └── Board (Work Surface) ─── den board <action>
           ├── [Web] Sheet (Web Screen) ─── den sheet <action>
           └── [Terminal] Session ─── den terminal <action> (Future)
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

For `sheet` commands, the target Web Board resolution follows this priority:
1. **Explicit Board ID**: Supplied via `--board <id>`.
2. **Adjacent Web Board**: Resolved relative to `callerBoardID` on its current Desk.
3. **Focused Board**: The currently focused Board on the active Desk, if it is a Web Board.
4. **First Web Board**: The first Web Board found on the active Desk.

### Global Options
- `--json`: Force output as structured JSON. When standard output is redirected or piped (non-TTY), JSON output is enabled automatically.
- `--board <id>`: Explicitly target a specific Board by its UUID.
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
| `den board close` | `[<id>]` | Close the specified Board or the target Web Board. | `den board close` |

### 3.3 `den desk` (Desks & Workspaces)
Commands operating on Desks within the Den.

| Command | Arguments | Description | Example |
|---|---|---|---|
| `den desk list` | None | List all Desks in the Den with ID, label, board count, and active status. | `den desk list` |

---

## 4. Output Contract (Dual Human + Agent Ergonomics)

### TTY Output (Human Mode)
When connected to an interactive terminal, `den` prints readable plain text and writes error messages to `stderr`.

```text
$ den sheet url
https://example.com/docs
```

### Non-TTY / `--json` Output (Agent Mode)
When piped or when `--json` is supplied, `den` outputs single-line JSON on standard output with standard Unix exit codes:

**Success (`exit 0`)**:
```json
{"success":true,"result":"https://example.com/docs"}
```

**Failure (`exit 1` or exit code > 0)**:
```json
{"success":false,"error":"No Web Board found on active Desk"}
```

---

## 5. Future Roadmap

- **`den sheet`**:
  - `den sheet back`, `den sheet forward`
  - `den sheet screenshot [--output <path>]`
  - `den sheet click <selector>`, `den sheet fill <selector> <text>`
- **`den board`**:
  - `den board remove [<id>]`
  - `den board focus <id>`
  - `den board new-terminal [<path>]`
- **`den desk`**:
  - `den desk switch <id|label>`
  - `den desk new [<label>]`
- **`den drawer`**:
  - `den drawer list`
  - `den drawer add <url>`
- **`den terminal`**:
  - `den terminal send <text>`
