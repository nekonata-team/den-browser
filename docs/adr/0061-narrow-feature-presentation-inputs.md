---
status: accepted
---

# Give Feature Presentation narrow inputs from Den composition

The direct Store access described below was an intermediate boundary. [ADR 0062](./0062-profile-state-source-and-presentation-models.md) subsequently removed that access from the presentation Models. Narrow Feature inputs remain in effect; current ownership is described in [the architecture guide](../architecture.md#shared-state-and-presentation-package-boundaries).

Feature Presentation should receive only the live state and operations it uses, with Den composition connecting window-local state and cross-Feature workflows. Use observable getters when live values must continue updating, and focused closures or bindings for operations; avoid per-Feature stores and broad protocols that mirror `DenController`. Drawer applies this boundary while keeping Drawer Placement in Den Application and its native Peek runtime concrete. Notifications receives live display items and actions to open a notification or request clearing; source lookup and cross-Desk navigation remain connected by Den.

`DenWindowComposition` owns window dependency assembly and Store-effect connection. `DenWindowModel` receives its Feature models and applies window presentation effects; it retains direct Store access for remaining operations until those responsibilities are separated. Commands receive Store and Model explicitly rather than obtaining the Store through the Model.
