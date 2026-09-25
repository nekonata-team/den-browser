---
status: accepted
---

# Add an Inspection Board for Joint Web Inspection

Safari Web Inspector is hosted by Safari and cannot be presented as a Board inside Den. Add an Inspection Board as a separate Board associated with a target Web Board's Current Sheet. Its initial scope is joint human and AI investigation of a selected element using page-derived DOM/ARIA, related labels and nodes, and page-originated console output and JavaScript errors; the native engine-computed accessibility tree and WebKit-internal diagnostics are not requirements. The PoC captured page console calls and JavaScript errors through a document-start bridge, but a public `NSAccessibilityProtocol` walk of a mounted `WKWebView` did not reveal the fixture button label; other macOS accessibility routes remain untested.

An Inspection Board is a Side Board of its target Web Board. The target and its Side Boards move and reorder together, remain adjacent with Side Boards after the target, and are centered as one span while retaining per-Board focus and width. Removing a Side Board leaves its target; removing a target removes its Side Boards, and one restore action restores the whole removed group.
