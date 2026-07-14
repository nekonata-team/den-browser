# Testing

Den Browser uses automated tests for stable product behavior and exploratory human validation for areas where automation is not reliable. The concrete PoC acceptance criteria live in [poc.md](./poc.md).

## Responsibilities

Automated unit tests own:

- `DenStore` and other pure state transitions, including board focus, ordering, moving, holding, placing, canceling, and closing.
- State persistence and restoration.
- Profile model coding, ordering, CRUD, corruption recovery, per-Profile Den restoration, and app-wide preference persistence.
- Routing Sheet Navigation callbacks and WebKit stores to their owning Profile.
- The pointer-focus state machine used to coordinate board selection and WebKit focus.

Stable product behavior should be covered by unit, integration, or end-to-end tests. Stable paths through Den Browser's own UI are candidates for future XCUITests.

Exploratory human validation is reserved for milestone checks that depend on macOS, WebKit, remote services, or visual judgment:

- Real interaction with `WKWebView`, including navigation and text entry.
- First-responder handoff between Den controls and web content.
- External web compatibility and authentication persistence.
- Performance and resource use.
- Liquid Glass, visual quality, and accessibility.

Human validation is exploratory, not a correctness guarantee. When it finds a reproducible regression, add an automated test where practical.

## Automated commands

Run from repository root. `just` commands use shared `Den Browser` scheme, local macOS destination, repository-local DerivedData, and disabled code signing.

```sh
just build
just test
just lint
just format
just check
```

`just lint` runs Xcode-bundled `swift-format` in strict mode, including style and enabled safety rules. `just format` applies same configuration. Builds treat compiler warnings as errors.

Before merge, use this standard order: build and unit tests, code review, then merge. Add exploratory validation when warranted, such as for UI behavior changes or milestone acceptance; use [poc.md](./poc.md) as the source of truth for concrete criteria.
