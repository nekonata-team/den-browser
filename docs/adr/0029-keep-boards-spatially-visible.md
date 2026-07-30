---
status: accepted
---

# Keep Boards spatially visible instead of adding an accordion layout

Den Browser will not add an accordion layout to a Desk. Boards in the Focused Desk represent established parallel work contexts, so the Board Strip keeps them ordered horizontally and shows as many at once as the window permits. Horizontal scrolling, persisted Board widths, and left-right Focus preserve this spatial relationship; overlapping Boards like a window manager's accordion would optimize mutually exclusive focus at the cost of simultaneous context.

Maximize Board remains a temporary Focus presentation rather than another Desk layout. It can give the Focused Board the available width while keeping the Board Strip's order and left-right navigation intact. Future improvements should refine that presentation, navigation, or indicators instead of introducing overlapping Board geometry.

The Drawer's vertical accordion is deliberate and does not contradict this decision. Drawer Items hold material whose Desk or Board context is not yet settled, and only one Drawer Preview needs to be live and prominent at a time. This boundary follows the spatial Board model in [ADR 0003](./0003-keyboard-first-den-operations.md) and the Drawer interaction model in [ADR 0025](./0025-den-level-drawer-for-unplaced-material.md).

Reconsider this decision only if Boards stop representing parallel contexts that benefit from simultaneous visibility. An accordion-first interface for mutually exclusive contexts would be a separate product model rather than another Den Browser layout mode.
