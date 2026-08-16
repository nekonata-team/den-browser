# Testing

Den Browser uses automated tests for stable product behavior and exploratory human validation for areas where automation is not reliable. The outcome-level PoC criteria live in [poc.md](./poc.md); this document defines the validation boundary rather than providing an exhaustive operation checklist.

## Responsibilities

Automated unit tests own:

- `DenStore` and other pure state transitions, including board focus, ordering, moving, holding, placing, canceling, and closing.
- State persistence and restoration.
- Terminal command parsing, Zellij and zmx command resolution, named theme resolution, and Web/Terminal/Zellij/zmx Board lifecycle transitions.
- Profile model coding, ordering, CRUD, corruption recovery, per-Profile Den restoration, Profile-window Desk assignment, and app-wide preference persistence.
- Routing Sheet Navigation callbacks and WebKit stores to their owning Profile.
- The pointer-focus state machine used to coordinate board selection and WebKit focus.

Stable product behavior should be covered by unit, integration, or end-to-end tests. XCUITests own native UI integration, including:

- SwiftUI-specific gesture identity (e.g. pointer drag-and-drop between Boards), which cannot be simulated in unit tests.
- Core mode transitions and state-transition cycles (e.g. Sheet input -> Den Mode -> returning to Sheet input and confirming re-focus/input capability).
- Creating a Terminal, Zellij, or zmx Board, entering Terminal Input, and removing it when the Shell, Zellij, or zmx process exits.

Per [ADR-0020](./adr/0020-test-critical-ui-workflows.md), each UI test is an independent user-visible workflow, not an exhaustive input permutation. Exhaustive shortcut mappings, state mutations (adding/removing boards), branches, and edge cases remain focused unit tests to prevent test suite hangs and maintain fast test execution.

### UI test readability

UI tests use a lightweight BDD-style structure. This is a readability convention, not a second test framework:

- `Given` describes the user-visible starting context.
- `When` describes a user action or meaningful transition.
- `Then` checks the observable result.

The `given`, `when`, and `then` helpers in `BDD.swift` record these sections with XCTest's `XCTContext` activities. They are available only to UI tests through a small marker protocol and must stay thin. Do not build a general-purpose fluent DSL or hide the scenario's important assertions behind helpers.

Keep scenario text in Den's domain language (`Desk`, `Board`, `Sheet`, `Drawer`, and `Drawer Preview`). Hide only mechanical details that obscure the behavior, such as repeated keyboard sequences, accessibility queries, fixture setup, or polling. The test body should still make the causal sequence and final assertions obvious.

Keep `Then` blocks assertion-only. Put input, navigation, dismissal, and other state-changing operations in `When` blocks. Use `assertEventually` for UI settling and animation boundaries; do not add sleeps or arbitrary delays.

UI tests launch with deterministic fixture state. Each test should request the smallest fixture that covers its
Given: one Board for single-Board workflows, two Boards when focus or ordering compares a pair, and three or more
only when the scenario needs them. The dedicated Desk fixtures should be used when a workflow needs a particular
Desk arrangement instead of constructing an unrelated Given through UI operations. The transition under test must
still be performed through the UI.
Profile documents use a fresh temporary directory, preferences use a dedicated defaults suite, and Sheets use a
non-persistent WebKit store with local data URLs. UI tests must not read or write the user's Profiles, preferences,
website data, window restoration, or external services. Terminal UI tests use an isolated `/bin/zsh -f` command and do not load the user's Ghostty configuration.

The separate `Den_BrowserUIPerformanceTests` class measures application launch with XCTest's
`XCTApplicationLaunchMetric`; it is not part of the default interaction test class. Run it explicitly when
checking launch performance:

```sh
just ui-test Den_BrowserUIPerformanceTests/testApplicationLaunchPerformance
xcrun xcresulttool get test-results metrics --path <path-to-xcresult>
```

Use the XCTest result bundle for per-test durations. Do not add ad hoc timers or sleeps to interaction tests.

Exploratory human validation is reserved for milestone checks that depend on macOS, WebKit, remote services, or visual judgment:

- Real interaction with `WKWebView`, including navigation and text entry.
- WebKit downloads, native save-panel access, Blob responses, and authenticated responses.
- First-responder handoff between Den controls and web content.
- External web compatibility and authentication persistence.
- Multiple-window placement and focus behavior across physical displays.
- Performance and resource use.
- Ghostty rendering, IME, Shell environment, Zellij/zmx detach and reattach behavior, and process cleanup.
- Liquid Glass, visual quality, and accessibility. On macOS, use Computer Use as an AX-based exploratory check for Den, Desk, Board, Overview, Drawer, Settings, app dialogs, and first-responder handoff. Record the accessibility boundary of external surfaces separately: WKWebView content belongs to the loaded site, and Ghostty's internal terminal content may not be exposed through the app AX tree.

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
[poc.md](./poc.md) as the source of truth for outcome-level PoC criteria. Do not add step-by-step procedures to
that document; turn reproducible findings into automated tests or tracked issues.
