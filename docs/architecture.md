# Architecture

Den Browser is organized around product features. The source tree keeps code that changes together close together, while platform-specific integration stays behind explicit boundaries.

This document describes the intended architecture. The current source tree is being migrated toward it incrementally, with path-only moves kept separate from behavior changes.

## Source organization

```text
Den Browser/Den Browser/
  App/
    app entry, configuration, and composition root
    keyboard command integration
    Settings/
      Settings scene and app-wide settings UI
  Features/
    Den/
      Den state, store, composition, and Den-level UI
      Store/
      Preferences/
      Board/
      Desk/
      Sheet/
      Overview/
    Profiles/
    SheetNavigation/
      settings UI, preferences, WebKit controller, and bundled script
  Platform/
    feature-independent OS integration, when it emerges
  Resources/
```

`Den`, `Profiles`, and `SheetNavigation` are the top-level Features. `Features/Den` is intentionally the largest Feature because a Den owns the workflows and invariants connecting Desks, Boards, Sheets, and Overview. Those folders are subfeatures or components, not independent top-level Features. A large cohesive Feature is preferable to false boundaries that make `DenStore` dependencies cyclic or scatter one workflow across the source tree.

## Dependency direction

```text
App -> Profiles -> Den -> SheetNavigation
App -------------> Den
App ---------------------> SheetNavigation
Profiles ----------------> SheetNavigation
App ------------------------------> Platform
```

- `App` assembles dependencies and owns application entry points. It does not contain feature behavior.
- `Features` owns product state, behavior, presentation, and feature-local UI.
- `Platform` owns only feature-independent operating-system integration. It is optional and may remain empty.
- Feature dependencies must remain acyclic.
- A Feature may depend on another Feature in one direction when a clear product ownership or lifecycle relationship explains that dependency. For example, a Profile owns one Den, so `Profiles -> Den` is allowed.
- Feature-to-Feature dependencies use the narrowest practical entry point and do not reach into the other Feature's private UI or implementation details.
- `App` coordinates scenes, windows, commands, navigation, and workflows that combine otherwise independent Features. Code is not promoted to `App` merely because two Features use it.
- Feature-specific AppKit, WebKit, persistence, or keyboard integration stays with its owning Feature or in `App`. Code moves to `Platform` only after a concrete feature-independent boundary emerges.
- `Platform` must not acquire feature policy. Temporary reverse dependencies are not hidden behind speculative protocols.

Folders communicate intent but do not enforce access control inside the shared Swift target. Dependency direction is maintained through review, focused tests, and keeping platform APIs narrow.

When a dependency would create a cycle, do not hide it behind an App coordinator or a generic shared type. Reconsider ownership, move orchestration to `App`, or narrow the exchanged data until the graph is acyclic.

## Den state and WebKit runtime

Persisted `DenState` remains separate from live `BoardRuntime` and `WKWebView` objects.

- `DenState` is the source of truth for Desk and Board identity, order, labels, widths, focus, and Current Sheet URLs.
- `BoardRuntime` owns live WebKit state, including each Board's in-memory Sheet Stack.
- Switching Desks detaches and reattaches live web views; it does not reconstruct persisted state or reload the Sheet Stack.
- Persistence never serializes `BoardRuntime` or `WKWebView`.

This boundary follows [ADR 0008](./adr/0008-codable-den-state-webview-runtime.md).

## Feature boundaries

### Den

Owns Den composition and the workflows connecting Desks, Boards, Sheets, and Overview. It also owns preferences that configure Den, Board, or Sheet behavior, even when those preferences apply across every Profile. `DenStore` remains one Feature store split into focused extensions under `Store`. Board, Desk, Sheet, and Overview remain inside this Feature because their UI and behavior depend on `DenStore`, while `DenView` composes them. Making them top-level Features would create immediate conceptual dependency cycles. Do not introduce repository, coordinator, or service layers solely to mirror folders.

### Profiles

Owns Profile identity, Profile-scoped persistence, website-data isolation, and Profile window lifecycle. A Profile owns one Den, so this Feature may depend on the Den Feature to create, restore, and present that Den. WebKit storage mechanics may live in `Platform`, while Profile policy remains in the feature.

### SheetNavigation

Owns optional Vim-style interaction within the Current Sheet: preferences, validation, settings UI, WebKit content-controller integration, and the bundled script. It does not own Board lifecycle or persisted Sheet state. Den injects the shared controller into each Board runtime and handles requests to open a link as another Board.

### Settings

Settings is not a Feature. `App/Settings` owns the Settings scene and its navigation. Feature-owned settings state and UI stay with the Feature that controls the behavior: Profile management belongs to `Features/Profiles`, Sheet Navigation settings belong to `Features/SheetNavigation`, and appearance, shortcuts, and Board layout preferences belong to `Features/Den`. The Settings scene assembles those screens without taking ownership of their behavior.

### Platform

Contains reusable operating-system integration rather than product concepts. Do not create a global Platform folder merely because code imports AppKit or WebKit. `BoardRuntime` and `BoardWebView` remain in Den because they own Board lifecycle. `SheetNavigationManager` remains in SheetNavigation because its WebKit integration implements that Feature. `KeyboardController` remains in `App` while it routes app-wide commands into Den behavior. A component moves to `Platform` only when its API is feature-independent and no reverse dependency on a Feature is required.

## Folder rules

- Prefer feature-local files over global `Models`, `Managers`, `Utilities`, or `Views` folders.
- Create a subfolder when it expresses a stable feature or platform boundary, not merely to hold one file.
- Promote code to `Platform` only after a feature-independent boundary genuinely exists; multiple callers alone are not sufficient.
- Keep source moves separate from behavior changes and dependency refactors.
- Do not edit `project.pbxproj` for ordinary moves under the file-system-synchronized root group.
- Preserve Objective-C bridging-header paths, private WebKit header references, target membership, and bundled resources during moves.

## Validation

Swift source moves require `just check`. Changes affecting Board or Desk interaction also run their focused UI tests. Resource moves must additionally verify that the bundled Sheet Navigation script loads at runtime.

Architecture decisions live in [docs/adr](./adr). Product terminology remains defined only in [CONTEXT.md](../CONTEXT.md).
