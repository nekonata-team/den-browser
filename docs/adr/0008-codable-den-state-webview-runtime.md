---
status: accepted
---

# Persist Den state separately from WebView runtime

Den Browser should persist desks, boards, labels, widths, current sheet URLs, and focus as Codable Den state, likely in JSON for the MVP. Live WKWebView instances are runtime objects and must not be treated as the source of truth for persisted state. Keeping persisted Den state separate from WebView runtime state makes restoration, testing, and later storage changes simpler.

## Desk switching and WebView scheduling

Only boards in the focused desk belong to the SwiftUI view hierarchy. When focus moves to another desk, its outgoing `BoardWebView` instances leave the window, while `DenStore` retains their `BoardRuntime` and `WKWebView` instances. Returning to a desk reattaches the existing web views; it does not reload them. This preserves each board's in-memory sheet state, including in-progress text.

WebKit's `WKPreferences.inactiveSchedulingPolicy` applies to a web view that is not in a window. Its documented default is `.suspend`, which fully suspends that web view's tasks. Den Browser relies on this default for inactive desks rather than retaining every desk's web views in the window. Media playback, media capture, and other user-interactive activity are exempt, so this is a scheduling behavior, not a hard resource limit.

Boards in the focused desk remain in the window even when horizontally offscreen, so this policy does not suspend them. Do not change the desk layout to retain inactive desks' web views in the window without reconsidering this lifecycle and its resource cost.

Reference: [WKPreferences.inactiveSchedulingPolicy — Apple Developer Documentation](https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property).
