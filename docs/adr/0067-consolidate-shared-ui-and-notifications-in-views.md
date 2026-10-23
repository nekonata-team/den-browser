# Consolidate shared UI and Notifications in DenViews

Consolidate shared visual primitives and the Notification View in `DenViews`, superseding the separate `DenDesign` module from [ADR 0059](0059-share-presentation-primitives.md).
Keep UI-independent presentation preferences in `DenModels` so shared rendering does not introduce a View dependency into Models.
