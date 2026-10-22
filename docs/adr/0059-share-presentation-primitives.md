---
status: superseded by ADR-0067
---

# Share presentation primitives through DenDesign

Visual tokens and reusable controls are shared across features, while window-specific layout and transitions depend on app composition. Put reusable presentation primitives in `DenDesign` and keep feature-specific geometry in the app, giving shared UI an explicit boundary without moving feature behavior.

Shared components moved to `DenViews` in [ADR 0067](0067-consolidate-shared-ui-and-notifications-in-views.md).
