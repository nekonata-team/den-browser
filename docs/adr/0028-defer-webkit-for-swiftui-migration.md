---
status: accepted
---

# Defer migration to WebKit for SwiftUI

Den Browser will keep its live Sheet runtimes on `WKWebView` instead of migrating them to `WebPage` and SwiftUI `WebView`. WebKit for SwiftUI covers much of the ordinary browsing surface, but the macOS 26.5 SDK does not expose enough control to preserve Den Browser's link routing, download lifecycle, programmatic page zoom, experimental Picture in Picture, and first-responder behavior without new AppKit escape hatches. Replacing the current bridge would therefore move complexity rather than remove it.

This decision was evaluated with Xcode and the macOS 26.5 SDK. Apple's web documentation may describe APIs newer than the installed SDK; an API is not treated as available until it compiles against the project's supported toolchain.

## Compatibility

| Current behavior | WebKit for SwiftUI | Decision |
| --- | --- | --- |
| Share one `WKWebsiteDataStore` across the Boards and Drawer Preview in a Profile | `WebPage.Configuration.websiteDataStore` accepts `WKWebsiteDataStore`. | Available. Preserve one Profile-owned data store per runtime configuration. |
| Install startup scripts and a message handler in an isolated `WKContentWorld` | `WebPage.Configuration.userContentController` accepts `WKUserContentController`, and `WebPage.callJavaScript` accepts a content world. | Available with redesign. Sheet Navigation actions should be associated with each `WebPage`; the current map is keyed by the underlying `WKWebView`, which SwiftUI does not expose. |
| Distinguish Command-click, Command-Shift-click, and Option-click | Apple's `WebPage.NavigationAction` documentation lists modifier information, but `modifierFlags` is absent from the macOS 26.5 SDK and a compile probe fails. | Blocking gap. Do not replace native link routing with page-injected click interception. |
| Route `target="_blank"` to a new Board | `NavigationDeciding` receives an action whose target is `nil` for a new browsing context and can cancel the navigation. | Available, subject to focused tests. |
| Choose a download destination and observe completion or failure | Navigation policy can request a download, but `WebPage` exposes no public hook for attaching Den Browser's `WKDownloadDelegate`. | Blocking gap. The save panel and completion/failure toast behavior from ADR 0027 cannot be preserved. |
| Handle JavaScript `alert`, `confirm`, and `prompt` | `WebPage.DialogPresenting` provides async handlers for all three operations. | Available. |
| Handle file and directory upload constraints | `DialogPresenting.handleFileInputPrompt` supplies `WKOpenPanelParameters` and returns selected URLs. | Available, subject to a sandboxed file/directory upload test. |
| Observe element fullscreen | SwiftUI `WebView` has `webViewElementFullscreenBehavior`, and `WebPage` exposes `fullscreenState`. | Available. |
| Toggle native Picture in Picture with the experimental preference | `WebPage.Configuration` does not expose `WKPreferences` or an equivalent PiP setting. JavaScript remains callable, but the private preference used by ADR 0021 cannot be configured. | Blocking gap while the experimental feature remains supported. |
| Apply persisted page zoom, navigate history, and reload | `WebPage` exposes its back-forward list, item loading, and reload. SwiftUI exposes magnification gestures but no equivalent to programmatically setting `WKWebView.pageZoom`. | Partial; page zoom is a blocking gap. |
| Move first responder to a focused Board or an opened Drawer Preview | SwiftUI focus APIs exist, but `WebView` does not expose the underlying `NSView` for `makeFirstResponder`. | Unconfirmed. A prototype must prove initial Vim input, pointer focus changes, fullscreen transitions, and Drawer Preview focus. |
| Keep live web objects out of persisted `DenState` | A runtime can own one `WebPage`, and Apple specifies that a `WebPage` binds to only one `WebView` at a time. | Available. `BoardRuntime` and `DrawerPreviewRuntime` remain the ownership boundary. |
| Preserve Sheet Navigation tests and critical UI tests | Pure routing and state tests can move to adapters, but modifier-click, download, and focus behavior cannot currently be exercised with equivalent production hooks. | Partial. Existing intent remains required after the blocking gaps close. |

## Consequences

`BoardRuntime`, `DrawerPreviewRuntime`, and their small `NSViewRepresentable` views remain deliberate AppKit/WebKit boundaries. New Sheet behavior should continue to be added to the runtime layer rather than persisted `DenState`.

Reevaluate this decision when the supported macOS SDK provides all of the following:

- modifier flags on `WebPage.NavigationAction` in the shipping SDK;
- a public download lifecycle hook with destination, completion, and failure control;
- programmatic page zoom;
- either the required PiP configuration or a decision to remove the experimental PiP feature;
- a proven SwiftUI focus path for Board and Drawer Preview web content.

At reevaluation, build an isolated prototype first. It must cover the compatibility table and the current Sheet Navigation and critical UI test intent before any production runtime is replaced.

## References

- [WebKit for SwiftUI](https://developer.apple.com/documentation/webkit/webkit-for-swiftui)
- [Building a cross-platform web browser](https://developer.apple.com/documentation/webkit/building-a-cross-platform-web-browser)
- [WebView](https://developer.apple.com/documentation/webkit/webview-swift.struct)
- [WebPage.Configuration](https://developer.apple.com/documentation/webkit/webpage/configuration)
- [WebPage.NavigationAction](https://developer.apple.com/documentation/webkit/webpage/navigationaction)
- [WebPage.DialogPresenting](https://developer.apple.com/documentation/webkit/webpage/dialogpresenting)
- [WKDownloadDelegate](https://developer.apple.com/documentation/webkit/wkdownloaddelegate)
