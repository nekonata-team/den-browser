---
status: accepted
---

# Keep Drawer as a single Den-level temporary context

Drawer remains one Den-wide place for material whose Desk or Board context is not settled. Drawer may gain alternate presentations, such as a floating or resizable layout, only when pointer and keyboard input still have one unambiguous owner. A visible Drawer must not become a persistent parallel work surface beside the Board.

Den Browser will not introduce a docked Drawer, Side, or Side Item merely to keep the same material visible across Desks. Docking changes more than geometry: it adds a concurrent input target, increases focus and shortcut burden, and turns the Drawer into a third kind of work surface without Desk or Board membership. The Drawer’s existing model—shared across Desks, temporary Preview, and one prominent Preview at a time—should remain intact.

Material that must remain visible across multiple Desks may be explored by extending the existing Board model, such as a possible Reference Board, in a separate decision. That direction must first define ownership, focus, lifecycle, and Desk membership rather than introducing another parallel surface concept.

## Consequences

- Layout changes are acceptable when they preserve a single input owner and do not add a new shortcut or focus model.
- Floating or resizable Drawer presentations remain candidates for future improvement.
- Any feature that adds a concurrent pointer or keyboard target requires an explicit product and domain decision; it is not a layout-only change.
- Future cross-Desk reference behavior should prefer extending an existing concept before introducing a new one.
