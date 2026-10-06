---
status: accepted
---

# Separate window presentation from DenStore

`DenStore` combined application operations with window presentation, making its responsibilities harder to follow. Keep application operations and per-window resources in `DenStore`, and Profile-shared data and runtime registries in `DenStorage`. Each window uses one Presentation ViewModel for its local workflows, shared by Views, Commands, and keyboard routing. Context-local ViewModels may own temporary state and cancellable presentation work. This keeps window presentation out of the Store while allowing multiple windows to present the same Den state.

Store-to-window communication uses plain effects delivered synchronously. This preserves effect order and lets keyboard input context update before the next event, while keeping Application independent of Presentation and UI state types. CLI and IPC continue to call Store operations directly. Current ownership and lifecycle details are described in [the architecture guide](../architecture.md#window-presentation-model).
