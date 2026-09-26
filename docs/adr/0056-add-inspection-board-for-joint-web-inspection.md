---
status: accepted
---

# Add an Inspection Board for Joint Web Inspection

Safari Web Inspector is hosted by Safari and cannot be presented as a Board inside Den. Add an Inspection Board for joint human and AI investigation of a selected element using page-derived DOM/ARIA, related labels and nodes, and page-originated console output and JavaScript errors; the native engine-computed accessibility tree and WebKit-internal diagnostics are not requirements. The PoC captured page console calls and JavaScript errors through a document-start bridge, but a public `NSAccessibilityProtocol` walk of a mounted `WKWebView` did not reveal the fixture button label; other macOS accessibility routes remain untested.

Inspection is Board content, while being a Side Board is an independent relationship. A Board Group contains one primary Board and zero or one Side Board. A target has at most one Side Board because current workflows need one companion surface; multiple tools belong inside that surface until a concrete parallel workflow justifies more.

A Board has one role in its Board Group: it is either the Primary Board or a Side Board. A Side Board stores the ID of its target Board; a standalone Board has the Primary Board role.

An Inspection Board is a Side Board of its target Web Board. A Board Group moves and reorders together, stays adjacent with its Side Board after the target, and centers as one span while retaining per-Board focus and width. Removing a Side Board leaves its target; removing a target removes its Side Board, and one restore action restores the whole removed group.
