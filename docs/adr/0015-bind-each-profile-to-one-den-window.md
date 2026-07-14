---
status: accepted
---

# Bind each Profile to one Den window

Each Profile owns exactly one Den presented in its own window, and every Board in that Den shares the Profile's persistent `WKWebsiteDataStore`. Profile and Den share one lifecycle: deleting a Profile also deletes its Den and website data. App preferences remain shared across profiles. Selecting a Profile with an open window brings that window forward; otherwise, it opens the Profile's Den window.

Persisted `ProfileState` has a stable Profile ID, name, color, and a `WebProfileStore` reference that is either `default` or `identified(UUID)`. The initial Profile uses WebKit's default store, while future profiles use identified stores. Keeping the store choice explicit and resolving it in one construction path avoids treating a missing Profile ID as the default store and extends ADR 0005 without requiring profile management in the MVP.
