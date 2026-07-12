---
status: accepted
---

# Resize boards at their boundaries

Pointer resizing uses the gap after a board rather than a permanently visible handle inside it. Dragging the gap changes only the board on its left, while later boards move with the desk's horizontal layout; the final board keeps the same interaction in the gap beyond its outer-right boundary. Resize handles stay visually quiet until hover or drag, and pointer resizing complements rather than replaces keyboard-first Board Width control.

Starting a boundary drag focuses its board but suppresses automatic centering so the grabbed boundary remains under the pointer. The Board Width updates continuously, remains constrained to the supported range, and is persisted when the drag ends.
