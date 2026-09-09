# Testing

Den Browser uses automated tests for stable product behavior and exploratory human validation for areas where automation is not reliable, building on the foundational architecture established in [ADR 0000](./adr/0000-poc-accepted.md). This document defines the validation boundary rather than providing an exhaustive operation checklist.

## XCUITest admission rule

XCUITest is an expensive exception, not the default for UI code. Adding a View, gesture, or user-visible behavior does not by itself justify a UI test.

Add a UI test only when all of the following are true:

- The behavior crosses a native UI boundary, such as SwiftUI-specific gesture identity (for example, pointer drag-and-drop), accessibility routing that is itself under test, or AppKit, WebKit, or Terminal responder boundaries. Ordinary Button clicks do not qualify.
- A unit test cannot observe the failure at that boundary.
- The test proves one independent user-visible workflow and its final outcome.

Before adding one, state which boundary it protects and why a unit test cannot observe it. Do not add UI tests for unit-observable behavior, ordinary Button clicks, visual/style choices, or every input variant of the same wiring. Exhaustive shortcut mappings, state transitions, branches, and edge cases belong in focused unit tests.

A concrete native boundary is Board input activation: the handoff from Board state and SwiftUI
updates to the Board's native input surface (`WKWebView` for a Web Board or the Ghostty view
for a Terminal Board).

For this boundary, a UI test qualifies only when it sends input after a pointer click, Den Mode
toggle, Desk switch, or Overview confirmation and observes a target-specific result. Board selection,
`DenStore` focus state, window titles, and routing decisions do not by themselves justify a UI test.
Unit tests cover the focus state machine; UI tests cover actual input delivery through the mounted
native surface.

If no such boundary exists, add or update the focused unit test instead. Use exploratory validation where automation is not reliable.

## Responsibilities

Automated unit tests own:

- Pure domain state transitions (focus, ordering, moving, removal, restoration, and navigation).
- State persistence, serialization, and schema migration.
- Command parsing, process resolution, and lifecycle state machines (Terminal, CLI, IPC).
- Profile lifecycle, workspace isolation, storage routing, and window assignment.
- App preferences and configuration persistence.
- Pointer-focus coordination and responder arbitration logic.

Unit tests must never read or write shared user defaults (`UserDefaults.standard`). Any test touching preferences or configuration must use isolated test containers or suite names.

### Unit test structure and boundary rules

Unit tests follow the Arrange-Act-Assert (AAA) pattern for consistency across the test suite, using explicit section comments (`// Arrange`, `// Act`, `// Assert`):

- `// Arrange`: Set up the initial state, fixtures, stubs, and isolated dependencies.
- `// Act`: Perform the single operation, transition, or method invocation under test.
- `// Assert`: Verify expected outcomes, state changes, and invariants with `#expect` or `#require`.

Boundary rules:
- **Direct boundary verification**: Test each component directly at its public interface. Do not exercise subsystem logic through outer orchestrators (e.g. test workspace state transitions directly, not through profile coordination).
- **One component per test suite**: Cross-cutting or independent components (such as preferences, IPC resolution, motion policies, or persistence models) belong in their own dedicated test files, not mixed into neighboring suites.
- **Focused state transitions**: Avoid long interleaved act-assert-act chains in a single test; split distinct state transitions, error branches, and edge cases into focused, single-purpose tests.


XCUITests own native UI integration, including:

- SwiftUI-specific gesture identity (e.g. pointer drag-and-drop between Boards), which cannot be simulated in unit tests.
- Board input activation across the native responder boundary, such as clicking an unfocused Board and sending input, or switching Desks and sending input without another click.
- Creating a Terminal, Zellij, or zmx Board, entering Terminal Input, and removing it when the Shell, Zellij, or zmx process exits.

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
- First-responder handoff involving IME, external sites, multiple windows, or other nondeterministic surfaces.
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

Before merge, run `just check`, then only the focused UI tests admitted by the rule above, then code review. Add
exploratory validation when warranted, such as for UI behavior changes or milestone acceptance. Turn
reproducible findings into automated unit or UI tests rather than manual checklists.
