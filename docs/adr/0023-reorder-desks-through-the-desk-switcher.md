---
status: accepted
---

# Reorder Desks through the Desk switcher

Desk order is persistent and gives numbered Desk navigation its meaning, so users need a direct way to adjust it. Reordering does not need a new keyboard command: Den Mode already reserves Shift plus movement for moving the Focused Board, and a new modifier family for Desk reordering would not fit the existing shortcut model.

Desk buttons in the Desk switcher support direct dragging. The dragged Desk lifts, nearby buttons preview the insertion order as their centers are crossed, and the order persists only when dropped inside the switcher. Dropping outside, pressing Escape, opening a temporary context, or deactivating the app restores the original order. Clicking a button still focuses its Desk, and the existing context menu remains available.

The feature moves only persisted `DeskState` order. It keeps Desk identity, Board state, focus within each Desk, and live Board runtimes intact. Zen View hides the Desk switcher, so it also makes reordering unavailable without adding a separate command path.
