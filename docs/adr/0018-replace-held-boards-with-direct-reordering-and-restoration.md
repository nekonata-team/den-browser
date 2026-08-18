---
status: accepted
---

# Replace Held Boards with direct reordering and lightweight restoration

Held Board began as an experiment for longer-distance Board Placement, but Overview and direct Desk movement now cover that work with less keyboard state. Den removes Held Board, its orange state, and its hold/place/restore commands. Board headers instead support direct drag reordering within one Desk, while keyboard movement and Overview remain the complete non-pointer alternatives.

Board Removal replaces permanent single-Board closing language. Removing a Board ends and releases its live `WKWebView`, while each Profile retains up to ten Recently Removed Boards during the current app run, including while that Profile window is closed. Board Restoration starts with the newest retained Board and recreates its `WKWebView` from the saved Current Sheet URL, restoring the same Board identity, label, width, First Sheet URL, and former placement when possible; repeated restoration can return older retained Boards. Restoration does not restore the Sheet Stack, page state, temporary maximization, or survive app restart, and deleting a Desk does not create a restoration candidate.

Header dragging uses the platform drag gesture threshold, focuses and visually lifts the dragged Board, clears temporary maximization, previews insertion as the Board center crosses neighboring centers, and commits and persists only on drop. It reorders only within the Focused Desk, auto-scrolls near horizontal edges, preserves the live Board runtime, and cancels when dropped outside the Board strip or when the interaction is interrupted.
