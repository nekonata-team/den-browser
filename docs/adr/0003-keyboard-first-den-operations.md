---
status: accepted
---

# Den operations are keyboard-first

Den Browser's own operations are keyboard-first: desk navigation, board navigation, board placement, board resizing, and sheet-stack movement must be possible without leaving the keyboard. Pointer interactions may support discoverability and occasional direct manipulation, but the core Den workflow should not depend on them. Web content inside sheets keeps its normal interaction model.

Shortcuts may be fixed in the MVP, but they should be designed with future customization in mind because Den shortcuts can conflict with OS and window-manager bindings.

For the MVP, Den-owned shortcuts use `Control` + `Option` as their shared prefix and avoid `Command`-based browser compatibility shortcuts. This makes Den spatial operations feel separate from conventional browser tab commands, while still leaving room for future shortcut customization when users need to avoid OS, window-manager, or input-method conflicts. The concrete shortcut map lives in [Shortcuts](../shortcuts.md).

Board and desk movement follow a spatial model: left/right moves focus across boards in the current desk, while up/down moves focus across desks. Adding Shift to those movement shortcuts moves the focused board itself, matching the window-manager pattern where Shift turns focus movement into item movement. Overview uses the same movement model without the Den prefix because web content is not active there, but movement changes an overview selection rather than the focused board until the user enters it. Return is reserved for creation-like actions such as duplicating the current sheet into a new board. `Command` + `T` is intentionally not provided because opening a board should feel like a Den action rather than opening a conventional tab, and `Control` + `Option` + `Q` is intentionally left unused because `Q` suggests quitting a larger scope such as a desk or the app.

Creating a board from the Open Board panel inserts it to the right of the focused board and then focuses the new board. This keeps board creation spatial: a new task branches from the current work instead of being appended to an abstract tab list.

Creating a desk from the New Desk panel inserts it after the focused desk and then focuses the new desk. The panel first focuses fuzzy Desk Preset search; arrow keys move the active candidate, Return or Tab confirms it and advances to its initial Desk Label, and Return from the label creates the Desk. Search-driven active candidates remain distinct from the confirmed Desk Preset. `Control` + `Option` + `N` opens this panel globally, including while overview is visible; overview itself has no dedicated creation mode.

Held Board and Board Placement were later removed by ADR 0018 after Overview and direct movement proved sufficient for longer-distance organization.
