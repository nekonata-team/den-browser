# Sheet operation examples

Replace sample URLs, selectors, names, and references with targets observed in the actual Sheet.

## 1. Open a Sheet and read its content

```sh
board_id="$(den board web new https://example.com --json | jq -er '.board_id')"
den sheet text --board "$board_id" --json
den sheet snapshot -i --board "$board_id" --json
```

`text` returns current visible content in `.text`; `snapshot` returns the semantic tree and element references in `.snapshot`. Board creation returns `.board_id` before content is necessarily ready. If the content you need has not loaded, wait for an element that identifies it, then read again.

For an existing Web Board, set `board_id` to its `.id` from the Board list. To navigate that Board, use `den sheet open <url> --board "$board_id" --json`.

## 2. Locate an element and click it

```sh
den sheet snapshot -i --board "$board_id" --json
```

If the returned snapshot identifies the intended link as `@e3 [link] "Documentation"`:

```sh
den sheet click @e3 --board "$board_id" --json
den sheet snapshot -i --board "$board_id" --json
```

Choose the target form that fits the evidence available:

- **Reference** (`@e3`): use when the intended element is identifiable in the snapshot.
- **CSS selector**: use a selector confirmed from inspected content, such as `a[href="/docs"]`.
- **Role and accessible name**: use a known control label without depending on its CSS structure, for example `den sheet click --role link --name Documentation --exact --board "$board_id" --json`. Both `--role` and `--name` are required.

For repeated labels, inspect a narrower region with `snapshot --within '<selector>'` and select its intended reference. Use `--full` when the compact snapshot omits the semantic content you need.

## 3. Fill a search form and wait for results

Assume inspection found `input[name="q"]`, a button named `Search`, and a results container `#results` that appears asynchronously after submission. The next step needs those results.

```sh
den sheet fill 'input[name="q"]' 'release notes' --board "$board_id" --json
den sheet click --role button --name Search --exact --board "$board_id" --json
den sheet wait '#results' --state visible --timeout 15 --board "$board_id" --json
den sheet snapshot --within '#results' --board "$board_id" --json
den sheet get text '#results' --board "$board_id" --json
```

`fill` supports inputs and textareas; pass `''` to clear a value. Snapshot output omits form values, so use `get value` to verify an input.

Choose a wait condition that distinguishes the new result from the previous state. If `#results` was already visible, its visibility alone does not prove the search finished. Use newly expected text (`wait --text 'Results for release notes'`) or a changed URL (`wait --url '*q=release*'`) when appropriate for the observed application.

Each `wait` accepts one condition: a selector/ref, `--text`, `--url`, `--load`, or `--fn`. `--state` accompanies a selector/ref; states are `attached`, `visible`, `hidden`, and `detached`. The default timeout is 10 seconds. `is` reads a state immediately; it does not wait for a transition.

## 4. Read element data and state

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
| `get value` | `.value` (may be an empty string) |
| `is enabled` | `.enabled` (boolean) |

Use `query --all` for a collection; without `--all`, query returns the first match. Unavailable query fields are omitted. Use `is visible` or `is checked` for `.visible` or `.checked`. A successful state query can return `false`; `.ok` indicates command success, not the element's state.

## 5. Scroll and inspect newly loaded content

Assume inspection established that scrolling loads more results asynchronously and that `#result-21` identifies a new item that must exist before scrolling it into view:

```sh
den sheet scroll down --board "$board_id" --json
den sheet wait '#result-21' --state attached --board "$board_id" --json
den sheet scroll '#result-21' --board "$board_id" --json
den sheet snapshot -i --board "$board_id" --json
```

`scroll down` moves within the Sheet; scrolling to a selector brings an existing element into view. For more items, repeat only until the requested content is found or the observed end condition is reached.

## When an operation fails

Failures return `.ok: false` and `.error`, with exit code 1. Inspect the error before continuing. Check the target with `den sheet url --board "$board_id" --json`, refresh the snapshot if the DOM changed, and verify that the wait condition describes the expected transition. A successful click or fill does not by itself establish that the application finished processing it.
