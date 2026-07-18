# Testing

Den Browser uses automated tests for stable product behavior and exploratory human validation for areas where automation is not reliable. The concrete PoC acceptance criteria live in [poc.md](./poc.md).

## Responsibilities

Automated unit tests own:

- `DenStore` and other pure state transitions, including board focus, ordering, moving, holding, placing, canceling, and closing.
- State persistence and restoration.
- Profile model coding, ordering, CRUD, corruption recovery, per-Profile Den restoration, and app-wide preference persistence.
- Routing Sheet Navigation callbacks and WebKit stores to their owning Profile.
- The pointer-focus state machine used to coordinate board selection and WebKit focus.

Stable product behavior should be covered by unit, integration, or end-to-end tests. XCUITests own stable input
routing through Den Browser's UI, including Den Mode entry from a focused Sheet, keyboard Board operations,
pointer focus, and basic Board dragging.

Per [ADR-0020](./adr/0020-test-critical-ui-workflows.md), each UI test is an independent user-visible workflow,
not an exhaustive input permutation. Current workflows cover organizing Boards from a focused Sheet with the
keyboard, removing and restoring a Board, and organizing Boards with the pointer. Shortcut mappings, branches,
and edge cases remain focused unit tests.

UI tests launch with a fixed three-Board fixture. Profile documents use a fresh temporary directory, preferences
use a dedicated defaults suite, and Sheets use a non-persistent WebKit store with local data URLs. UI tests must
not read or write the user's Profiles, preferences, website data, window restoration, or external services.

Exploratory human validation is reserved for milestone checks that depend on macOS, WebKit, remote services, or visual judgment:

- Real interaction with `WKWebView`, including navigation and text entry.
- First-responder handoff between Den controls and web content.
- External web compatibility and authentication persistence.
- Performance and resource use.
- Liquid Glass, visual quality, and accessibility.

Human validation is exploratory, not a correctness guarantee. When it finds a reproducible regression, add an automated test where practical.

## Automated commands

Run from repository root. `just` commands use the shared `Den Browser` scheme, local macOS destination, and
repository-local DerivedData. Build and unit-test commands disable code signing; macOS UI tests use normal local
development signing and separate `.derived-data-ui` output because their runner must control the app process.

```sh
just build
just test
just ui-test
just lint
just format
just check
```

`just lint` runs Xcode-bundled `swift-format` in strict mode, including style and enabled safety rules. `just format` applies same configuration. Builds treat compiler warnings as errors.

Before merge, use this standard order: build and unit tests, applicable UI tests, code review, then merge. Add
exploratory validation when warranted, such as for UI behavior changes or milestone acceptance; use
[poc.md](./poc.md) as the source of truth for concrete criteria.
