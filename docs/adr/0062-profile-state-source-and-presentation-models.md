---
status: accepted
---

# Separate the Profile state source from observable presentation Models

`DenApplication` owns one observable Profile source with read-only snapshots and a separate write capability, while `DenModels` owns window presentation and privately retains concrete operations supplied by composition.
This avoids per-Feature copies of authoritative state and lets Models run without UI/native SDKs; Swift Observation is accepted in Application to avoid a custom notification bridge.
App supplies native and persistence bindings, and UI and IPC share Application operations without making screen Models the IPC entry point.
