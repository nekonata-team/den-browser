---
status: accepted
---

# Separate window presentation from DenStore

The names `DenStore`, `DenStorage`, and ViewModel below describe the implementation when this decision was made. [ADR 0062](./0062-profile-state-source-and-presentation-models.md) later separated the shared state source from native adapters and moved presentation Models into their own package. The separation of window presentation and synchronous effect delivery remains in effect.

`DenStore` combined application operations with window presentation, making its responsibilities harder to follow. Keep application operations and per-window resources in `DenStore`, and Profile-shared data and runtime registries in `DenStorage`. Each window uses one Presentation ViewModel for its local workflows, shared by Views, Commands, and keyboard routing. Context-local ViewModels may own temporary state and cancellable presentation work. This keeps window presentation out of the Store while allowing multiple windows to present the same Den state.

Store-to-window communication uses plain effects delivered synchronously. This preserves effect order and lets keyboard input context update before the next event, while keeping Application independent of Presentation and UI state types. CLI and IPC continue to call Store operations directly. Current ownership and lifecycle details are described in [the architecture guide](../architecture.md#window-presentation-model).
