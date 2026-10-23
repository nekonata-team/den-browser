---
status: accepted
---

# Defer migration to WebKit for SwiftUI

Den Browser keeps live Sheet runtimes on `WKWebView`: evaluation against the macOS 26.5 SDK found that [WebKit for SwiftUI](https://developer.apple.com/documentation/webkit/webkit-for-swiftui) could not preserve modifier-click routing, download lifecycle control, programmatic page zoom, and the current native Picture in Picture configuration, while first-responder behavior remained unproven.
Migrating would therefore move complexity into new AppKit escape hatches rather than remove the existing bridge.
Reconsider when the supported SDK and an isolated prototype can preserve those behaviors and pass the relevant [native-boundary tests](../testing.md), verifying API availability by compilation rather than assuming web documentation matches the installed SDK.
