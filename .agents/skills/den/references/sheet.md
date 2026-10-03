# Sheet operation examples

Replace sample values with targets observed in the Sheet.

## Open a Sheet and read its content

```sh
board_id="$(den board web new https://example.com --json | jq -er '.board_id')"
den board web text --board "$board_id" --json
den board web snapshot -i --board "$board_id" --json
```

`text` returns `.text` (visible content); `snapshot` returns `.snapshot` (semantic tree and references). Board creation returns `.board_id` before the Sheet is ready; if needed content is not loaded, wait for an identifying element and read again.

For an existing Web Board, use its `.id` from the Board list as `board_id`; navigate with `den board web navigate <url> --board "$board_id" --json`.

## Locate an element and click it

```sh
den board web snapshot -i --board "$board_id" --json
```

If the returned snapshot identifies the intended link as `@e3 [link] "Documentation"`:

```sh
den board web click @e3 --snapshot --board "$board_id" --json
```

Choose a target form based on available evidence:

- **Reference** (`@e3`): use when the intended element is identifiable in the snapshot.
- **CSS selector**: use a selector confirmed from inspected content, such as `a[href="/docs"]`.
- **Role and accessible name**: use a known control label without depending on its CSS structure, for example `den board web click --role link --name Documentation --exact --board "$board_id" --json`. Both `--role` and `--name` are required.

Use semantic ancestor areas in the snapshot to distinguish repeated labels. If the intended area is still unclear, inspect it with `snapshot --within '<selector|ref>'` and select its intended reference. Use `--full` when the compact snapshot omits the semantic content you need. `--snapshot` captures the command's resulting state without waiting for later page activity.

## Fill a search form and wait for results

Assume inspection found `input[name="q"]`, a `Search` button, and a `#results` container that appears asynchronously.

```sh
den board web interact - --snapshot --board "$board_id" --json << 'EOF'
fill 'input[name="q"]' 'release notes'
click --role button --name Search --exact
wait '#results' --state visible --timeout 15
EOF
den board web get text '#results' --board "$board_id" --json
```

`fill` supports inputs and textareas; pass `''` to clear. Snapshots include compact text-control values, including empty values, except password inputs; use `get value` to read the complete value. For a single action, use `den board web fill @e2 'query' --snapshot --json`. For asynchronous updates, use a condition-based `wait --snapshot` or put `wait` at the end of `interact`.

Choose a condition that confirms new results. If `#results` was already visible, wait for new expected text (`wait --text 'Results for release notes'`) or a changed URL (`wait --url '*q=release*'`) instead.

Each `wait` accepts one condition: a selector/ref, `--text`, `--url`, `--load`, or `--fn`. `--state` applies to selectors/refs and supports `attached`, `visible`, `hidden`, or `detached`. Timeout defaults to 10 seconds. `is` checks state immediately.

## Batch actions with `interact`

Use `interact` to batch known actions from inline text, a file, or stdin (`-`). It resolves the target Web Board once and runs steps in order, stopping at the first failure. By default it returns completion metadata without capturing a snapshot. Add `--snapshot` for one final semantic snapshot, or `--snapshot --full` for the full semantic tree. `--full` requires `--snapshot`.

Scripts use standard `den board web` action syntax, one action per line or separated by `;`; blank lines and `#` comments are ignored. Pass a file by path (`den board web interact ./actions.den --board "$board_id" --json`).

For example, via heredoc / stdin:

```sh
den board web interact - --snapshot --board "$board_id" --json << 'EOF'
fill @e2 "Buy groceries"
press Enter
fill @e2 "Read release notes"
press Enter
EOF
```

Or as an inline script:

```sh
den board web interact "click @e1; fill @e2 'query'; press Enter" --snapshot --board "$board_id" --json
```

Actions share the current Sheet state; intermediate snapshots are omitted. If an action may replace its target, do not reuse that ref. Use a role/name or selector that can be resolved again, wait for the next state, or split the batch and take a new snapshot.

For example, this handles a control that is removed and then added asynchronously:

```sh
den board web interact - --snapshot --board "$board_id" --json << 'EOF'
click --role button --name "Remove" --exact
wait #checkbox --state detached
click --role button --name "Add" --exact
wait #checkbox --state attached
EOF
```

The requested final snapshot does not wait for asynchronous activity unless the script includes a condition-based `wait`. On success, read `.completed_actions` and `.snapshot` when requested. On failure, inspect `.error`, `.completed_actions`, `.failed_action_index` (zero-based when present), and any best-effort `.snapshot` when requested. A failed batch may have completed earlier actions; do not replay the whole script without checking the current state. If only final snapshot capture failed, the actions may all have completed and `.failed_action_index` can be absent.

## Read element data and state

For a Sheet with inspected result links and a search form:

```sh
den board web query '#results a' --visible --all --fields text,attr:href --board "$board_id" --json
den board web get text '#results' --board "$board_id" --json
den board web get attr '#results a' href --board "$board_id" --json
den board web get count '#results a' --board "$board_id" --json
den board web get value 'input[name="q"]' --board "$board_id" --json
den board web is enabled 'button[type="submit"]' --board "$board_id" --json
```

Read the corresponding JSON fields:

| Operation | Result |
| --- | --- |
| `query` | `.elements[]`, with `.ref`, `.visible`, and requested fields such as `.text` and `.attributes.href` |
| `get text` | `.text` |
| `get attr` | `.attribute` |
| `get count` | `.count` |
| `get box` | `.box` (with `.x`, `.y`, `.width`, `.height`) |
| `get value` | `.value` (may be an empty string) |
| `is enabled` | `.enabled` (boolean) |

`query --all` returns every match; without it, only the first. Unavailable fields are omitted. `is visible` and `is checked` return `.visible` and `.checked`. A successful state query may return `false`; `.ok` indicates command success.

## Scroll and inspect newly loaded content

For infinite scrolling where `#result-21` appears after scrolling:

```sh
den board web scroll down --board "$board_id" --json
den board web wait '#result-21' --state attached --board "$board_id" --json
den board web scroll '#result-21' --snapshot --board "$board_id" --json
```

`scroll down` moves within the Sheet; scrolling to a selector brings an existing element into view. Repeat until you find all requested items or confirm the end.
