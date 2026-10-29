# Web Board operation examples

Examples use `den board web` to operate on a Web Board's Current Sheet. Replace example URLs, selectors, and control names with observed targets. Check the installed CLI's `den board web <command> --help` for available options.

## Choose the observation you need

| Goal | Command | Read from JSON |
| --- | --- | --- |
| Understand page content with headings, links, tables, and code | `read` | `.markdown`, with `.title` and `.url` |
| Read plain text or an API response body | `text` | `.text`, a string |
| Find controls and their semantic context | `snapshot` | `.snapshot`, with element references |
| Inspect visual layout or Canvas content | `screenshot` | `.screenshot_path`, a PNG file path |
| Extract selected DOM data | `query` or `get` | Requested element fields |

## Choose or create a Web Board

Reuse an existing Web Board when appropriate: obtain its `.id` from `den board list --json` and assign it to `board_id`. To create a separate work surface:

```sh
board_id="$(den board web new https://example.com --json | jq -er '.board_id')"
```

`new` returns `.board_id` before loading completes. Pass that ID with `--board "$board_id"` on subsequent operations. Use `navigate` to change the Current Sheet in the existing Board instead of creating another Board.

## Read structured Web content

After waiting for the intended page content, read it as Markdown:

```sh
den board web read --board "$board_id" --json
```

To avoid surrounding navigation and footers, scope the read to an observed content element. For example, if inspection identified one `main` region:

```sh
den board web read --within main --board "$board_id" --json
```

`--within` also accepts a current element reference. A missing or ambiguous scope fails instead of reading the whole page. Without a scope, `read` includes navigation and footers; it preserves structure without summarizing or inferring article content, and can produce more text than `text`. Shadow DOM and iframe contents are not included.

## Read plain text or an API response

Navigate and wait for the destination before reading its response:

```sh
den board web navigate https://api.example.test/items/42 --board "$board_id" --json
den board web wait --fn 'location.href === "https://api.example.test/items/42" && document.readyState === "complete"' --board "$board_id" --json
den board web text --board "$board_id" --json
```

For navigation and asynchronous actions throughout these examples, wait for a condition that distinguishes the new state. A load-state check alone can observe the outgoing document; an already-visible results container can match old results. For redirects, use the final URL; for unchanged URLs, identify the new content. Use condition-based waits, not fixed delays (`wait --help` lists options).

`.text` remains a string for JSON responses. HTML returns visible body text; documents such as XML without an HTML body return root-element text. An empty response body can produce an empty string.

## Locate an element and click it

```sh
den board web snapshot --board "$board_id" --json
```

If the returned snapshot identifies the intended link as `@e3 [link] "Documentation"`:

```sh
den board web click @e3 --snapshot --board "$board_id" --json
```

Alternatively, use an inspected CSS selector such as `a[href="/docs"]`, or `click --role link --name Documentation --exact`. Both role and name are required and must match one visible element; `--exact` does not disambiguate duplicates. CSS selectors resolve the first match. For repeated labels, use `snapshot --within '<selector|ref>'` and the intended reference; use `--full` for omitted content.

After navigation or element replacement, take a fresh snapshot or resolve a known selector/role again, including between batch steps.

## Follow a link while keeping the source page

If the latest snapshot identifies the intended link as `@e3`, open it separately and retain both Board IDs:

```sh
linked_board_id="$(den board web click @e3 --new-board --board "$board_id" --json | jq -er '.board_id')"
den board web wait --text 'Documentation overview' --board "$linked_board_id" --json
den board web read --board "$linked_board_id" --json
```

`--new-board` requires a link with an `href`. Keep `board_id` for the source; close the temporary destination when finished with `den board close --board "$linked_board_id" --json`.

## Check the URL and return through history

After following a link in the same Board, read `.url` to check the current address. To return to a known results page:

```sh
den board web url --board "$board_id" --json
den board web back --board "$board_id" --json
den board web wait --text 'Results for release notes' --snapshot --board "$board_id" --json
```

`forward` moves forward again; `reload` reloads the Current Sheet. Use the same Board targeting and destination waits.

## Fill a search form and wait for results

Assume inspection found `input[name="q"]`, a `Search` button, and a `#results` container. The new results include the text `Results for release notes`:

```sh
den board web interact - --snapshot --board "$board_id" --json << 'EOF'
fill 'input[name="q"]' 'release notes'
click --role button --name Search --exact
wait --text 'Results for release notes' --timeout 15
EOF
den board web get text '#results' --board "$board_id" --json
```

`fill` replaces input/textarea values; pass `''` to clear. Use `get value` for the complete value.

## Use keyboard input and editable controls

For a search form that submits on Enter, replace the search example's `click` step with these batch actions:

```text
focus 'input[name="q"]'
press Enter
```

`press` sends key events to the active element; `press Escape` can dismiss a popup whose focused control handles that key.

For an inspected rich editor, use `den board web type '#editor[contenteditable="true"]' 'Additional text' --snapshot --board "$board_id" --json`. `type` inserts text rather than replacing the value; omit its target to type into the focused element.

## Batch actions with `interact`

The search example uses `interact` to fix the target Board, run steps in order, and stop at the first failure. Add `--snapshot` for a final observation, or `--snapshot --full` for the full tree. Snapshots do not wait for asynchronous updates; include a final `wait` when needed.

Scripts use `den board web` action syntax without the command prefix, one action per line or separated by `;`. Blank lines and `#` comments are ignored. Pass an inline script, a file path, or stdin (`-`).

Read `.completed_actions` and the requested `.snapshot`. On execution failure, inspect `.error`, the zero-based `.failed_action_index` when present, and the current state before retrying: earlier actions remain applied. If only final snapshot capture failed, all actions may have completed and `.failed_action_index` can be absent.

Argument or script-syntax errors can fail before execution with stderr and no JSON; inspect stderr when stdout is empty.

## Read element data and state

For a Sheet with inspected result links and a search form:

```sh
den board web query '#results a' --visible --all --fields text,attr:href --board "$board_id" --json
den board web get value 'input[name="q"]' --board "$board_id" --json
```

Read `.elements[]` with `.ref`, `.text`, and `.attributes.href`, or `.value` for `get value`. `query --all` returns every match; otherwise only the first. Unavailable fields are omitted. For immediate boolean checks, use `is visible`, `is enabled`, or `is checked`; `false` is a valid result, not a command failure. See `get --help` for other data operations.

## Scroll and inspect newly loaded content

For infinite scrolling where `#result-21` appears after scrolling:

```sh
den board web scroll down --board "$board_id" --json
den board web wait '#result-21' --state attached --board "$board_id" --json
den board web scroll '#result-21' --snapshot --board "$board_id" --json
```

`scroll down` moves within the Sheet; scrolling to a selector brings an existing element into view. Repeat until you find all requested items or confirm the end.

## Inspect the rendered page

When layout, images, or Canvas content matters, capture the visible Current Sheet:

```sh
den board web screenshot /tmp/den-page.png --board "$board_id" --json
```

Open `.screenshot_path` with an image-viewing tool. Only the visible area is captured; scroll and capture again for other areas.

## Diagnose an unexpected response with HTTP status (optional)

For an empty or unexpected body, check the loaded main page's HTTP status:

```sh
den board web status --board "$board_id" --json
```

`.status` is the main-page HTTP code or `null` when unavailable, including while loading or for local files. `.ok` reports command success, including HTTP 404/500. This reads the recorded response without another request; it does not report `fetch`/XHR or iframe responses.
