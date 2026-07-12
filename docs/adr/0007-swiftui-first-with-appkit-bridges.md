---
status: accepted
---

# Use SwiftUI first with AppKit bridges

Den Browser should use SwiftUI for the application shell, desk and board layout, labels, overlays, commands, and settings. AppKit should be introduced where SwiftUI does not provide enough control, especially for embedding WKWebView through NSViewRepresentable and for low-level keyboard or window behavior. This keeps the app modern and fast to build while still allowing native macOS WebView control where the Den model needs it.
