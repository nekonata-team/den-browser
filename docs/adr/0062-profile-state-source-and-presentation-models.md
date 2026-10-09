---
status: accepted
---

# Separate the Profile state source from observable presentation Models

UDF and a single source of truth require shared data to have one owner and a controlled update path. Keep the Profile's data in the UI-independent `DenApplication` package, with read-only `DenStateStore` snapshots and a separately held write capability. Keep persisted Domain values unchanged. Native resources and persistence callbacks stay outside this core. The shared Store uses Swift Observation directly; this standard framework dependency is accepted to avoid a custom notification bridge while keeping SwiftUI and Presentation dependencies out of Application.

Move the Store-independent Drawer, Notifications, Overview, Desk Filter, and Open Board Models into `DenPresentation`, which depends only on Domain values and Observation. Use Model names for their presentation role, and `DenWindowModel` for window presentation. App composition supplies live data and operations. This enforces the extracted dependency boundaries without duplicating the authoritative shared state or creating a Store per Feature. Remaining native workflows and window operations are still in the app target and require subsequent extraction before the entire Application boundary is compiler-enforced.

Extend this layer boundary to independent operations in `DenApplication` and persistence/native implementations in `DenInfrastructure`. App composes their concrete bindings. Feature groups classify responsibility within these modules rather than recreating every layer under each Feature; current placement and extraction progress are described in the architecture guide.
