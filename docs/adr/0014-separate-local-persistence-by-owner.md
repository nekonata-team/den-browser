---
status: accepted
---

# Separate local persistence by owner

Den Browser stores local data according to its owner instead of combining it in one settings blob. Each versioned JSON `PersistedProfile` document contains `schemaVersion`, `ProfileState`, and `DenState`, while a small profile index records available profiles and their order. Typed `AppPreferences` remain app-wide and use individually stored `UserDefaults` keys plus a `preferences.schemaVersion` migration cursor; website data remains owned by WebKit. Missing preference versions are treated as version 0, migrate one version at a time, and are recorded only after each step completes. Versions newer than the app supports are not downgraded. This extends ADR 0008, lets Profile data and preferences migrate independently, and prevents WebKit runtime data from leaking into the Den model.

If a Profile document cannot be decoded, Den Browser preserves the unreadable file before starting with a fresh Profile and Den. The first public format is schema version 1; no migration from prerelease formats is required.
