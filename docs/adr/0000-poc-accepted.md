---
status: accepted
---

# PoC Accepted

The initial proof of concept explored whether a macOS SwiftUI and AppKit application hosting embedded `WKWebView` instances could support Den's spatial, keyboard-first interaction model for long-running web and terminal work.

The core question has been answered affirmatively:
- Multi-profile web isolation and session survival (including major AI chat providers) across restarts operate reliably using independent `WKWebsiteDataStore` instances.
- The spatial paper-workspace model—desks holding multiple horizontally arranged boards, preserved in-memory sheet navigation stacks, and persistent board states—coexists seamlessly with embedded `WKWebView` and Ghostty-powered terminal surfaces.
- Persisted `DenState` cleanly decouples from live runtime objects (`BoardRuntime`, `TerminalRuntime`), ensuring lightweight and reliable state restoration without serializing WebKit or terminal internals.
- Keyboard routing successfully arbitrates app-level Den Mode shortcuts while web sheets or terminal buffers hold active focus.

The PoC phase is concluded and its architectural foundation accepted. The original criteria and exploratory checks in `docs/poc.md` (as of commit `d08737f`) are satisfied and superseded by this decision. Moving forward, outcome-level correctness is protected by focused automated unit tests and native boundary XCUITests rather than recurring manual PoC checklists.
