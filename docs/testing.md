# Testing

Unit tests protect state and operation contracts; XCUITest covers native UI boundaries that unit tests
cannot observe ([ADR 0020](./adr/0020-test-critical-ui-workflows.md)).
Exploratory validation covers environment-dependent or visual behavior.

## XCUITest admission rule

Add a UI test only when all three conditions hold:

- The behavior crosses a native boundary: SwiftUI gesture identity, accessibility routing, or AppKit,
  WebKit or Terminal responder handoff.
- A unit test cannot observe the failure at that boundary.
- It proves one independent user-visible workflow and its final outcome.

Before adding one, name the boundary and explain why unit coverage is insufficient.
Ordinary Button clicks, styling and input permutations do not qualify.
Shortcut mappings, state transitions and edge cases belong in focused unit tests.

For Board activation, send input after a click, mode change, Desk switch or Overview confirmation
and observe a target-specific result. Selected Board state, window titles and routing decisions alone
do not prove input reached the mounted native surface.

## Unit test boundaries

| Target | Contract |
| --- | --- |
| Domain/Application | Actor-independent rules, decisions, state transformations and shared workflows |
| Models | Live Observation, shared state access, window-local state, transitions and cancellation |
| Infrastructure | Filesystem/bitmap I/O and OS process sampling |
| App | Native SDK/resource connections, Profile/window lifecycle and UI/IPC integration |

Test each component through its own interface; use App integration tests for contracts involving native
resources or their owners. Assert observable outcomes rather than Task identity.
Keep setup dependencies visible and avoid constructing an outer application graph for a component test.

Group tests by the responsibility they verify, with separate files for independent components.
Board-kind tests live under `Board/Web`, `Board/Terminal` or `Board/Inspection`.
Do not reproduce every source layer as a test folder.
Shared helpers belong under `Support` and test resources under `Fixtures`.

Use explicit `// Arrange`, `// Act` and `// Assert` sections and keep each scenario focused on one contract.
Tests touching preferences must use isolated suites or containers, never `UserDefaults.standard`.

## UI test structure and isolation

Use Given/When/Then activities through the thin `BDD.swift` helpers.
Keep scenario names in Den's domain language and leave the causal action and final assertions visible.
`Then` blocks contain assertions; input and other mutations belong in `When`.
Use `assertEventually` for settling, avoid arbitrary sleeps, and paste long text rather than typing it character by character.

Choose the smallest deterministic fixture that covers the workflow.
Prepare unrelated state through fixtures; perform the transition under test through the UI.
Each run uses temporary Profile documents, an isolated defaults suite, non-persistent WebKit data and local URLs.
Tests must not touch user Profiles, preferences, website data, window restoration or external services.
Terminal tests use `/bin/zsh -f` and do not load the user's Ghostty configuration.

## Exploratory validation

Use exploratory checks where automation cannot reliably cover:

- Real websites, authentication, downloads, Blob responses and save panels.
- IME/responder handoff, multiple windows/displays, Ghostty rendering and session reattachment.
- Liquid Glass, accessibility, resource use and performance.

On macOS, use Computer Use for app-owned UI and responder checks.
Treat external accessibility surfaces separately: WKWebView content belongs to the site and
Ghostty's terminal content may not be exposed through the app AX tree.
Reproducible findings should gain focused automated coverage where practical.

## Automated commands

Run from the repository root:

```sh
just build
just test
just test packages
just test ui
just lint
just format
just check
just test architecture
```

The default unit recipe includes independent SwiftPM tests for Application, Models, Infrastructure and
IPCProtocol, without App, WebKit or Ghostty. It also builds Views and Demo; Domain builds as a dependency.
All package checks treat compiler warnings as errors. Application test suites are explicitly nonisolated, so
requiring MainActor for a rule breaks compilation before execution. Shared operation tests also run
against a plain state owner without Models; Model integration tests protect the Observation bridge. Hosted tests cover native mounting, resource lifetime and App integration.
Unit tests disable code signing; UI tests use development signing and separate `.derived-data-ui` output.

`just lint` runs the [source guards](../.ast-grep/README.md), swift-format in strict mode and SwiftLint.
Builds treat compiler warnings as errors. Package dependencies are compiler-enforced; import scans do not
prove isolation between App source groups, event destinations or resource lifetimes.

Before merge, run `just check` and the focused UI tests admitted above, then review the diff.
Add exploratory validation when the affected boundary requires it.
Use XCTest result bundles for durations; launch/resource measurement is documented in
[benchmarking.md](./benchmarking.md).
