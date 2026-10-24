---
status: accepted
---

# Keep one Model module and actor-independent Application operations

`DenModels` owns the observable Profile state source and window/Feature Models in one target, while `DenApplication` owns shared operation workflows without MainActor or Observation dependencies.
App composition supplies synchronous read/write capabilities and persistence bindings; this keeps UI and IPC on the same Application operations without making Models the IPC entry point or copying authoritative state.
The capabilities are non-Sendable and preserve the owner's isolation and synchronous notification/commit/save order; this separation does not imply background execution or pure functions without side effects.
