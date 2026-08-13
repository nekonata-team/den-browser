---
status: accepted
---

# Present distinct Desks in Profile windows

A Profile may present its Den in multiple windows, with each window assigned one distinct Desk. Profile selection still brings an existing Profile window forward. A second window is opened deliberately from a Desk's context menu; ordinary Desk selection does not create windows.

Persisted `DenState`, Desk presets, recent items, `BoardRuntime` objects, and `TerminalRuntime` objects remain shared per Profile. Each window has its own `DenStore` presentation state, including its presented Desk, modes, filters, panels, layout metrics, Drawer Preview runtime, and toast. Runtime callbacks are rebound to the window currently presenting their Board. This preserves one source of truth and one live runtime per Board without making transient window state global.

The same Desk cannot be assigned to two windows. Selecting a Desk assigned elsewhere brings its window forward. Opening the current Desk in a new window first moves the source window to another unassigned Desk; the action is unavailable when no replacement exists. Closing a window quietly releases its Desk assignment. Window-to-Desk assignments are not part of Profile persistence.

Resetting the Profile-wide Den closes its additional windows before rebuilding the single initial Desk. This avoids leaving windows without a valid Desk assignment.

This supersedes ADR 0015's one-window restriction while retaining its Profile ownership, lifecycle, and website-data isolation decisions.
