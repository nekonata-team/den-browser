# Architecture

Den Browser is organized around product features. The source tree keeps code that changes together close together, while platform-specific integration stays behind explicit boundaries.

This document describes current and intended boundaries; path-only moves remain separate from behavior changes.

## Platform baseline

The app and test targets support macOS 26.0 and later. Availability checks and fallback paths must reflect versions that can actually run under this baseline. In particular, `if #available(macOS 26.0, *)` is redundant and should not be introduced, nor should code remain solely for versions below macOS 26.0. Checks for runtime presence of private or optional selectors are a separate concern and must be justified by the API's runtime behavior, not by the deployment target.

## Source organization

```text
Den Browser/Den Browser/
  App/
    app entry, configuration, keyboard integration, and Settings composition
  Features/
    Den/
      Domain/                 aggregate Den state, Essentials, and Notifications
      Application/            shared storage, window store, and cross-domain operations
      Presentation/           Den composition, Overview, panels, Toast, and visual design
      Infrastructure/         state encoding and process-resource sampling
      Preferences/
    Desk/
      Domain/                 Desk state and Desk Presets
      Presentation/           switcher, panels, and preset UI
    Board/
      Domain/                 identity, kind, grouping, and input resolution
      Presentation/           strip, rail, layout, surfaces, and common panels
      Web/                    Domain, Presentation, and Infrastructure
      Terminal/               Domain, Application, Presentation, and Infrastructure
      Inspection/             Domain, Presentation, and Infrastructure
      Tutorial/               Domain and Presentation
    Drawer/
      Domain/
      Presentation/
      Infrastructure/
    Profiles/
      Domain/
      Application/
      Presentation/
      Infrastructure/
    Web/
      Domain/                 shared URL rules and Web input values
      Infrastructure/         shared WebKit runtime, DOM, interactions, and screenshots
    Extensions/
    SheetNavigation/
  IPC/
    Protocol/                 typed command, payload, request, and response definitions
    Transport/                socket client/server mechanics
    Application/              request handling and ambient target resolution
  Platform/
    feature-independent OS integration and native SurfaceHost
  PrivateWebKit/
    private WebKit API declarations
  Resources/
```

Features are source ownership groups inside one Swift target, not independently isolated modules or stores. Den owns aggregate state, the workflows joining Desks, Boards, and Drawer, and the composition of the Den window. Desk, Board, and Drawer own their data and presentation in sibling folders; Board kind-specific code stays under Board. Overview, Notifications, Essentials, Toast, and shared Den visual design stay in Den because they present or coordinate the complete Den.

The shared Web group contains code used by Web Boards, Drawer Preview, and Sheet Navigation. A Web Board's state, view, and runtime belong to `Board/Web`; shared URL policy, DOM execution, and the base WebKit runtime belong to `Web`. Sheet is not a Web-only implementation boundary, so there is no generic Sheet runtime folder or shared Sheet interface.

## Dependency direction

- `App` assembles scenes, windows, commands, and dependencies. It does not acquire feature behavior merely because multiple Features use it.
- `Domain` contains state and product rules. It does not depend on `DenStore`, SwiftUI, AppKit, WebKit, or live runtime objects. Domain groups may reference one another according to the product model: Den contains Desks, and Desks contain Boards.
- `Application` owns operation sequencing, shared or window-local state, and lifecycle coordination. `DenStore` remains the shared operation entry point; its extensions live in `Den/Application/Operations`. No new per-domain store is introduced merely to match the folder tree.
- `Presentation` owns views, geometry, visual tokens, and display-only extensions. Existing views may use `DenStore` across source groups. Native view adapters may use their concrete runtimes.
- `Infrastructure` owns concrete WebKit, Terminal, persistence, and process integration. Application code can call these implementations directly; folder organization alone does not justify a protocol, repository, or coordinator.
- `Platform` contains only feature-independent operating-system integration. Product URL rules and Den lifecycle remain with their owners.
- IPC is an application adapter shared with the bundled CLI. Protocol definitions are compiled into both targets; socket transport does not own Board or Profile policy.
- Feature-specific settings UI remains with its owner. `App/Settings` assembles those screens.

Folders communicate ownership but do not enforce access control in the shared Swift target. Judge dependencies by the role of the code, not by assuming every sibling Feature is an independent module. Keep domain rules free of UI and runtime dependencies, and use the narrowest practical entry point for cross-domain operations.

WebExtension integration uses the existing `WebExtensionHost` boundary. Board and Drawer supply their WebKit instances and URL-loading callbacks; Extensions owns tab registration and never imports Den runtime types. Profile-window keyboard ownership follows [keyboard-input.md](./keyboard-input.md).

## Den state and live runtimes

Persisted Profile data remains separate from live Web and Terminal runtime objects.

- `DenState` is the source of truth for Desk and Board identity, order, labels, widths, focus, Board kinds and their saved state, Drawer Items, and the expanded Drawer Item identity used to restore a Preview.
- `DenStorage` also holds Profile-owned persisted Desk Presets and Recent Items. These are persisted alongside `DenState` but remain separate data collections.
- `WebBoardRuntime` owns live WebKit state, including each Web Board's in-memory Sheet Stack.
- `BoardState.kind` distinguishes Web, Inspection, Terminal, and Tutorial Boards and carries their kind-specific state. A Board presents Sheets; Web Boards have a Sheet Stack, while Terminal Boards present one Sheet backed by a live Terminal Session. Tutorial Boards and their progress are session-only and stay out of persisted DenState and Desk Presets. Terminal session choices (Shell, Zellij, and zmx) belong to Terminal Board state; URLs and Vim-style Sheet Navigation settings belong to Web Board state.
- `TerminalRuntime` owns one libghostty surface and Shell, Zellij, or zmx process. One controller is used per Terminal Board.
- Each Profile has one shared `DenStorage` for persisted data, Profile-shared transient state, and live runtime registries. Profile-shared transient state includes Notifications, active drag state, Recently Removed Boards, and discarded Drawer Item restoration history. Each Profile window has a `DenStore` for its presented Desk and window-local presentation state.
- `DenView` renders only the Desk assigned to its window. Shared runtime storage retains both runtime types across Desk and window changes; detached Terminal views stop rendering without ending their process. A detached TerminalRuntime also runs low-frequency app ticks until its surface is visible again or the runtime is disposed; this follows [ADR 0040](./adr/0040-tick-detached-terminal-runtimes.md).
- Window-local state includes Den Mode, filters, panel presentation and workflows, layout metrics, Drawer Preview runtime, active download presentation, and Toast presentation. Each panel owns its transient draft values and `FocusState`; a draft that must survive panel replacement, such as Open Board input, remains in the window-local `DenStore`. Window-to-Desk assignment is managed by `ProfileManager` and is not persisted.
- zmx session discovery is window-local. Each `DenStore` owns one `ZmxSessionsModel`, which owns session listing, filtering, selection, deletion, and their asynchronous Tasks. The model is stopped when the zmx Sessions context closes, so late command results cannot update a closed panel. `DenStore` supplies the current zmx client and coordinates opening a Board or returning to the Open Board panel.
- Persistence never serializes WebKit objects, terminal processes, terminal screens, or scrollback.

This boundary follows [ADR 0008](./adr/0008-codable-den-state-webview-runtime.md).

Terminal embedding and its security boundary follow [ADR 0032](./adr/0032-embed-terminal-boards-with-libghostty.md).

## Feature boundaries

### Den

Owns Den aggregate state, shared and window-local storage, composition, and operations connecting Desks, Boards, Drawer, and Overview. `DenStore` remains one store split into focused operation extensions; it owns exclusive panel presentation and commit operations. `DenStorage` is a separate Application file containing Profile-shared data and runtime registries. Window-local workflow types are separate from the store implementation.

Desk owns Desk state and preset data. Board owns shared Board state and grouping plus its Web, Terminal, Inspection, and Tutorial implementations. Drawer owns Drawer Items, its view, and Preview runtime. Their views may depend on Den's application operations without changing data ownership. `ZmxSessionsModel` stays in `Board/Terminal/Application` and owns session state and command Tasks, while Den coordinates Board creation, focus, and panel transitions.

Den also owns preferences for shared presentation behavior and the Den-wide Notification list. `IPC/Application` connects external CLI and MCP requests to active Profile windows through existing domain operations, following [ADR 0047](./adr/0047-integrate-den-cli.md) and [ADR 0055](./adr/0055-add-den-mcp-server.md).

### Profiles

Owns Profile identity, Profile-scoped persistence, website-data isolation, and Profile window lifecycle. A Profile owns one Den and may present distinct Desks from it in multiple windows, so this Feature may depend on the Den Feature to create, restore, and present that Den. WebKit storage mechanics may live in `Platform`, while Profile policy remains in the feature.

`ProfileManager` owns the lifecycle binding: one lazily created `MV3WebExtensionHost` per Profile and one extension window per Profile Window using that host. When content blocking is enabled, the first live Web Board, Drawer Preview, or explicit extension popup/options request creates the host. Creating or focusing an empty or Terminal-only Profile Window does not load the extension. Ordinary Profiles use a persistent extension controller identified by their stable Profile ID; Private Den uses a non-persistent extension controller so its extension state does not carry into another session. Host implementation, curated descriptors, on-demand installation, resource loading, and WebKit controller integration belong to `Extensions`.

### Extensions

Owns curated WebExtension descriptors, permissions, on-demand installation, resource loading, and the per-Profile MV3 WebKit host. It does not own Profile identity or website-data policy; `Profiles` supplies lifecycle and `WKWebsiteDataStore` bindings. It does not own Den concepts; `Den` supplies Board and Drawer runtime registration at the narrow host boundary. Arbitrary extension installation remains outside this boundary.

### SheetNavigation

Owns optional Vim-style interaction within the Current Sheet: preferences, validation, settings UI, WebKit content-controller integration, and the bundled script. It does not own Board lifecycle or persisted Sheet state. Den injects the shared controller into each Board runtime and handles requests to open a link as another Board.

### Settings

Settings > Web provides app-wide Search Engine and automatic Picture in Picture choices. The search choice persists across relaunches and applies when search terms are opened, including saved Recent Items and Essentials. Automatic Picture in Picture moves a playing video from the Focused Board into native Picture in Picture when the user switches Desks; it is disabled by default. Explicit URLs and existing Sheets remain unchanged.

Settings is not a Feature. `App/Settings` owns the Settings scene and its navigation. Feature-owned settings state and UI stay with the Feature that controls the behavior: Profile management belongs to `Features/Profiles`, Sheet Navigation settings belong to `Features/SheetNavigation`, and appearance, shortcuts, and Board layout preferences belong to `Features/Den`. The Settings scene assembles those screens without taking ownership of their behavior.

### Platform

Contains reusable operating-system integration rather than product concepts. Do not create a global Platform folder merely because code imports AppKit or WebKit. `TextInputComposition` is a feature-independent IME composition helper shared by Den, Sheet Navigation, and App settings. `SurfaceHost` is a generic native-view host shared by Board kind adapters and Drawer Preview; its API uses only AppKit views and generic request values. `WebBoardRuntime` and `BoardWebView` remain in `Board/Web` because they own Web Board lifecycle. `SheetNavigationManager` remains in SheetNavigation because its WebKit integration implements that Feature. `KeyboardController` remains in `App` while it routes app-wide commands into Den behavior. A component moves to `Platform` only when its API is feature-independent and no reverse dependency on a Feature is required.

## Folder rules

- Prefer feature-local files over global `Models`, `Managers`, `Utilities`, or `Views` folders.
- Use Domain, Application, Presentation, and Infrastructure within a source group only where they clarify existing responsibilities. Keep small groups flat rather than creating empty or single-file layer scaffolding.
- Promote code to `Platform` only after a feature-independent boundary genuinely exists; multiple callers alone are not sufficient.
- Keep source moves separate from behavior changes and dependency refactors.
- Do not edit `project.pbxproj` for ordinary moves under the file-system-synchronized root group.
- Preserve Objective-C bridging-header paths, private WebKit header references, target membership, and bundled resources during moves.

## Validation

Validation boundaries follow [testing.md](./testing.md). Swift source moves require `just check`; resource moves must additionally verify that the bundled Sheet Navigation script loads at runtime. Changes to Feature ownership or dependency direction must update a relevant ADR or add one.

Architecture decisions live in [docs/adr](./adr). Product terminology remains defined only in [CONTEXT.md](../CONTEXT.md).
