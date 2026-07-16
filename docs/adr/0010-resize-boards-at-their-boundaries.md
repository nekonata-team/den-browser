---
status: accepted
---

# Resize boards at their boundaries

Pointer resizing uses the gap after a board rather than a permanently visible handle inside it. Dragging the gap changes only the board on its left, while later boards move with the desk's horizontal layout; the final board keeps the same interaction in the gap beyond its outer-right boundary. Resize handles stay visually quiet until hover or drag, and pointer resizing complements rather than replaces keyboard-first Board Width control.

Starting a boundary drag focuses its board but suppresses automatic centering so the grabbed boundary remains under the pointer. The Board Width updates continuously, remains constrained to the supported range, and is persisted when the drag ends.

Den Mode also provides a keyboard-first bulk resize for the Focused Desk. The user chooses how many Boards should fit the current window; Den calculates one Board Width from the available horizontal area and applies it persistently to every Board in that Desk. A result below the minimum Board Width is unavailable, but no maximum is needed because the calculation cannot exceed the current window; fitting one Board therefore always uses the full available width. Running the command again recalculates from the latest window width, while later window changes do not automatically alter Board Widths. Bulk resizing clears temporary maximization, preserves and centers the Focused Board.
