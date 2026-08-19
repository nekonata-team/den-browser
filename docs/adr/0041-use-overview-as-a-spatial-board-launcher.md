---
status: accepted
---

# Use Overview as a Spatial Board Launcher

Overview is a temporary Den presentation primarily for moving into a selected Board, while also providing a spatial map of Desks and their Boards. It keeps each Desk as an ordered horizontal row and represents persisted Board width proportionally, extending the spatial Board model in [ADR 0029](./0029-keep-boards-spatially-visible.md) without introducing freeform Board coordinates or overlapping layouts.

Clicking selects a Board; Return or double-clicking enters the selected Desk and Board, while dragging reorders or moves Boards between Desks. Double-clicking an empty Desk enters that Desk. Web and Terminal Boards share this map and interaction model but remain visually distinct through type icons, labels, and semantic type tint, while the active Profile color carries selection identity. Overview uses lightweight identity metadata, such as a favicon when available with a generic fallback, rather than live Web or Terminal screenshots.

This keeps Overview a fast Board launcher and orientation surface. It does not create a second browser surface, add a freeform layout model, or introduce a screenshot cache for Overview.
