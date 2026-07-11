# Testing

Den Browser uses automated tests for stable product behavior and exploratory human validation for areas where automation is not reliable. The concrete PoC acceptance criteria live in [poc.md](./poc.md).

## Responsibilities

Automated unit tests own:

- `DenStore` and other pure state transitions, including board focus, ordering, moving, holding, placing, canceling, and closing.
- State persistence and restoration.
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

Run from the repository root. Both commands use the shared `Den Browser` scheme, the local macOS destination, a repository-local DerivedData directory, and disabled code signing.

```sh
xcodebuild build \
  -project "Den Browser/Den Browser.xcodeproj" \
  -scheme "Den Browser" \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project "Den Browser/Den Browser.xcodeproj" \
  -scheme "Den Browser" \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data \
  -only-testing:'Den BrowserTests' \
  CODE_SIGNING_ALLOWED=NO
```

Before merge, use this standard order: build and unit tests, code review, then merge. Add exploratory validation when warranted, such as for UI behavior changes or milestone acceptance; use [poc.md](./poc.md) as the source of truth for concrete criteria.
