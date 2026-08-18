---
status: accepted
---

# Keep Boards spatially visible instead of stacking them

Den Browser will not add a Board Stack, tabbed Board group, accordion, or other overlapping Board layout to a Desk. Boards in the Focused Desk represent established parallel work contexts, so the Board Strip keeps them ordered horizontally and shows as many at once as the window permits. Horizontal scrolling, persisted Board widths, and left-right Focus preserve this spatial relationship; overlapping Boards would optimize mutually exclusive focus at the cost of simultaneous context and would turn Board Navigation back into tab selection.

Content that belongs to one work context stays inside one Board. Web navigation remains in its Sheet Stack. Related shells for one terminal task belong to a Zellij session inside one Zellij Board. If web or terminal work represents different established contexts, it remains in separate, spatially visible Boards. Users who want mutually exclusive tabbed web contexts can use a conventional browser rather than making Den duplicate that product model.

Maximize Board remains a temporary Focus presentation rather than another Desk layout. It can give the Focused Board the available width while keeping the Board Strip's order and left-right navigation intact. Future improvements should refine that presentation, navigation, or indicators instead of introducing overlapping Board geometry.

The Drawer's vertical accordion is deliberate and does not contradict this decision. Drawer Items hold material whose Desk or Board context is not yet settled, and only one Drawer Preview needs to be live and prominent at a time. This boundary follows the spatial Board model in [ADR 0003](./0003-keyboard-first-den-operations.md) and the Drawer interaction model in [ADR 0025](./0025-den-level-drawer-for-unplaced-material.md).

Reconsider this decision only if repeated use shows a stable category of independent Board contexts that must retain separate identity and runtime while sharing one spatial position. An interface organized around mutually exclusive stacked contexts would otherwise be a separate product model rather than another Den Browser layout mode.
