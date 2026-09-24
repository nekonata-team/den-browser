# Sheet operation examples

Replace sample values with targets observed in the Sheet.

## Open a Sheet and read its content

```sh
board_id="$(den board web new https://example.com --json | jq -er '.board_id')"
den sheet text --board "$board_id" --json
den sheet snapshot -i --board "$board_id" --json
```

`text` returns `.text` (visible content); `snapshot` returns `.snapshot` (semantic tree and references). Board creation returns `.board_id` before the Sheet is ready; if needed content is not loaded, wait for an identifying element and read again.

For an existing Web Board, use its `.id` from the Board list as `board_id`; navigate with `den sheet open <url> --board "$board_id" --json`.

## Locate an element and click it

```sh
den sheet snapshot -i --board "$board_id" --json
```

If the returned snapshot identifies the intended link as `@e3 [link] "Documentation"`:

```sh
den sheet click @e3 --board "$board_id" --json
den sheet snapshot -i --board "$board_id" --json
```

Choose a target form based on available evidence:

- **Reference** (`@e3`): use when the intended element is identifiable in the snapshot.
- **CSS selector**: use a selector confirmed from inspected content, such as `a[href="/docs"]`.
- **Role and accessible name**: use a known control label without depending on its CSS structure, for example `den sheet click --role link --name Documentation --exact --board "$board_id" --json`. Both `--role` and `--name` are required.

For repeated labels, inspect a narrower region with `snapshot --within '<selector>'` and select its intended reference. Use `--full` when the compact snapshot omits the semantic content you need.

## Fill a search form and wait for results

Assume inspection found `input[name="q"]`, a `Search` button, and a `#results` container that appears asynchronously.

```sh
den sheet fill 'input[name="q"]' 'release notes' --board "$board_id" --json
den sheet click --role button --name Search --exact --board "$board_id" --json
den sheet wait '#results' --state visible --timeout 15 --board "$board_id" --json
den sheet snapshot --within '#results' --board "$board_id" --json
den sheet get text '#results' --board "$board_id" --json
```

`fill` supports inputs and textareas; pass `''` to clear. Snapshots omit form values; use `get value` to verify them.

Choose a condition that confirms new results. If `#results` was already visible, wait for new expected text (`wait --text 'Results for release notes'`) or a changed URL (`wait --url '*q=release*'`) instead.

Each `wait` accepts one condition: a selector/ref, `--text`, `--url`, `--load`, or `--fn`. `--state` applies to selectors/refs and supports `attached`, `visible`, `hidden`, or `detached`. Timeout defaults to 10 seconds. `is` checks state immediately.

## Batch actions with `interact`

Use `interact` to batch two or more known actions from inline text, a file, or stdin (`-`); it returns one final semantic snapshot. Add `--full` when you need the full semantic tree.

Scripts use standard `den sheet` action syntax, one action per line or separated by `;`; blank lines and `#` comments are ignored. Pass a file by path (`den sheet interact ./actions.den --board "$board_id" --json`).

For example, via heredoc / stdin:

```sh
den sheet interact - --board "$board_id" --json << 'EOF'
fill @e2 "Buy groceries"
press Enter
fill @e2 "Read release notes"
press Enter
EOF
```

Or as an inline script:

```sh
den sheet interact "click @e1; fill @e2 'query'; press Enter" --board "$board_id" --json
```

Actions share the current Sheet state; intermediate snapshots are omitted. If an action may replace its target, do not reuse that ref. Use a role/name or selector that can be resolved again, wait for the next state, or split the batch and take a new snapshot.

For example, this handles a control that is removed and then added asynchronously:

```sh
den sheet interact - --board "$board_id" --json << 'EOF'
click --role button --name "Remove" --exact
wait #checkbox --state detached
click --role button --name "Add" --exact
wait #checkbox --state attached
EOF
```

`wait` waits for a condition, not for an arbitrary duration. On success, read `.snapshot` and `.completed_actions`. On failure, inspect `.error`, `.snapshot`, `.completed_actions`, and `.failed_action_index` before deciding whether to refresh the snapshot or retry.

## Read element data and state

For a Sheet with inspected result links and a search form:

```sh
den sheet query '#results a' --visible --all --fields text,attr:href --board "$board_id" --json
den sheet get text '#results' --board "$board_id" --json
den sheet get attr '#results a' href --board "$board_id" --json
den sheet get count '#results a' --board "$board_id" --json
den sheet get value 'input[name="q"]' --board "$board_id" --json
den sheet is enabled 'button[type="submit"]' --board "$board_id" --json
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
den sheet scroll down --board "$board_id" --json
den sheet wait '#result-21' --state attached --board "$board_id" --json
den sheet scroll '#result-21' --board "$board_id" --json
den sheet snapshot -i --board "$board_id" --json
```

`scroll down` moves within the Sheet; scrolling to a selector brings an existing element into view. Repeat until you find all requested items or confirm the end.
