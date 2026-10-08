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
      Application/            shared storage, window store, operations, and operation feedback
      Presentation/           window ViewModel, Den composition, panels, Toast, and window layout
      Preferences/
    Desk/
      Presentation/           switcher, panels, and preset UI
    Board/
      Application/            input interpretation and launch validation
      Presentation/           strip, rail, layout, surfaces, and common panels
      Web/                    Presentation and Infrastructure
      Terminal/               Application, Presentation, and Infrastructure
      Inspection/             Presentation and Infrastructure
      Tutorial/               Presentation
    Drawer/
      Presentation/
      Infrastructure/
    Essentials/
      Presentation/           prefix panel and settings
    Notifications/
      Presentation/           notification list and selection
    Overview/
      Presentation/           cross-Desk overview and selection
    BoardActivity/
      Presentation/           live Board resource usage
      Infrastructure/         process-resource sampling
    Profiles/
      Application/
      Presentation/
      Infrastructure/
    Web/
      Infrastructure/         shared WebKit runtime, DOM, interactions, and screenshots
    Extensions/
    SheetNavigation/
  IPC/
    Transport/                socket client/server mechanics
    Application/              request handling and ambient target resolution
  Platform/
    feature-independent OS integration and native SurfaceHost
  PrivateWebKit/
    private WebKit API declarations
  Resources/
Packages/DenDomain/
  Sources/DenDomain/
    Board/{Inspection,Terminal,Tutorial,Web}
    Den, Desk, Drawer, Essentials, Notifications, Profiles, Web
Packages/DenDesign/Sources/DenDesign/
  shared visual tokens, metrics, motion, panels, and controls
Packages/DenIPCProtocol/Sources/DenIPCProtocol/
  Foundation-only CLI/app wire DTOs
```

Features are source ownership groups inside the app target, not independently isolated modules or stores. Den owns aggregate state, the workflows joining Desks, Boards, and Drawer, and the composition of the Den window. Desk, Board, Drawer, Essentials, Notifications, Overview, and BoardActivity own their data or feature-specific presentation in sibling folders; Board kind-specific code stays under Board. Toast, Den backgrounds, confirmation dialogs, and window layout stay in Den because they present or coordinate the complete Den. Den retains the operations connecting Essentials and Notifications to Boards and the transitions between their panels and other window contexts.

Selected shared Domain values live in one `DenDomain` Swift package target. Its Foundation-only model closure is shared by the app and unit tests; it contains no Stores, workflows, persistence adapters, presentation, or platform runtimes. A single module preserves cross-feature model references such as Den-to-Desk and Board-to-Web state. The app and unit-test targets import this product directly.

`DenDesign` owns shared visual tokens, color palettes, fixed layout metrics, motion choices and presets, panel styling, and reusable controls. This includes normal, Den Mode, and Private Den background palettes; Den Presentation selects and renders them from the current window state. The package defines `DenLayout` and `DenMotion`; Den Presentation extends `DenLayout` with Board width and height calculations that use window geometry and Board constraints, while Board Presentation extends `DenMotion` with `boardTransition`. The app and unit tests import `DenDesign`; it does not depend on Feature state, Stores, or workflows. Selection navigation and drag geometry remain presentation behavior outside the package. This boundary follows [ADR 0059](./adr/0059-share-presentation-primitives.md).

`DenIPCProtocol` contains Foundation-only Codable command, operation, request, response, and payload DTOs shared by the app, bundled CLI, and unit tests. A `DenIPCRequest` wraps one `DenIPCOperation` and caller context; operations carry typed `BoardTarget` or `DeskTarget` values, with required IDs on operations that cannot use ambient resolution. `DenIPCResponse` carries a tagged `DenIPCOperationResult` and the resolved target context. The CLI and MCP adapters consume the result's flat public JSON projection; MCP also uses the resolved target metadata. The package has no dependency on the app, UI, or `DenDomain`. The app owns request handling and target resolution, while the bundled CLI and MCP server parse their inputs and send operations over the socket. The app and CLI ship together and use these shared types directly, without a legacy flat-JSON adapter. This boundary follows [ADR 0060](./adr/0060-share-ipc-wire-types.md).

The CLI groups commands by Board kind under [ADR 0051](./adr/0051-structure-den-cli-by-board-kind.md), while MCP exposes action-first tools with JSON Schema arguments under [ADR 0055](./adr/0055-add-den-mcp-server.md). Both adapters call the same typed IPC operations and keep product terms such as Sheet, even when their public names differ.

The shared Web group contains code used by Web Boards, Drawer Preview, and Sheet Navigation. A Web Board's state, view, and runtime belong to `Board/Web`; shared URL policy, DOM execution, and the base WebKit runtime belong to `Web`. Sheet is not a Web-only implementation boundary, so there is no generic Sheet runtime folder or shared Sheet interface.

## Dependency direction

- `App` assembles scenes, windows, commands, and dependencies. It does not acquire feature behavior merely because multiple Features use it.
- `DenDesign` provides shared visual presentation without depending on Feature models or operations. Motion preference storage remains in AppPreferences; its visual choice type belongs to DenDesign.
- `Domain` contains state and product rules. It does not depend on `DenStore`, Application-owned operation events, SwiftUI, AppKit, WebKit, or live runtime objects. Domain groups may reference one another according to the product model: Den contains Desks, and Desks contain Boards.
- `DenDomain` is the compiler-enforced module for the moved shared Domain values. It depends only on Foundation and keeps the app's Swift 6 MainActor isolation policy; application behavior stays in the app target.
- `Application` owns operation sequencing, application state, and runtime lifecycle coordination. `DenStore` remains the operation entry point; its extensions live in `Den/Application/Operations`. No new per-domain store is introduced merely to match the folder tree.
- `Presentation` owns views, window-local UI models, geometry, visual tokens, and display mappings as independent functions. Existing views may use `DenStore` across source groups. Native view adapters may use their concrete runtimes.
- `Infrastructure` owns concrete WebKit, Terminal, persistence, and process integration. Application code can call these implementations directly; folder organization alone does not justify a protocol, repository, or coordinator.
- `Platform` contains only feature-independent operating-system integration. Product URL rules and Den lifecycle remain with their owners.
- IPC is an application adapter shared with the bundled CLI. `DenIPCProtocol` supplies the typed operation envelope and response DTOs; socket transport does not own Board or Profile policy.
- Feature-specific settings UI remains with its owner. `App/Settings` assembles those screens.

Folders communicate ownership but do not enforce access control between source groups that remain in the app target. `DenDomain`, `DenDesign`, and `DenIPCProtocol` enforce their module boundaries. Judge remaining dependencies by the role of the code, not by assuming every sibling Feature is an independent module. Keep domain rules free of UI and runtime dependencies, and use the narrowest practical entry point for cross-domain operations.

WebExtension integration uses the existing `WebExtensionHost` boundary. Board and Drawer supply their WebKit instances and URL-loading callbacks; Extensions owns tab registration and never imports Den runtime types. Profile-window keyboard ownership follows [keyboard-input.md](./keyboard-input.md).

## Den state and live runtimes

Persisted Profile data remains separate from live Web and Terminal runtime objects.

- `DenState` is the source of truth for Desk and Board identity, order, labels, widths, focus, Board kinds and their saved state, and Drawer Items. Drawer selection and Preview expansion are window-local ViewModel state.
- `DenStorage` also holds Profile-owned persisted Desk Presets and Recent Items. These are persisted alongside `DenState` but remain separate data collections.
- `WebBoardRuntime` owns live WebKit state, including each Web Board's in-memory Sheet Stack.
- `BoardState.kind` distinguishes Web, Inspection, Terminal, and Tutorial Boards and carries their kind-specific state. A Board presents Sheets; Web Boards have a Sheet Stack, while Terminal Boards present one Sheet backed by a live Terminal Session. Tutorial Boards and their progress are session-only and stay out of persisted DenState and Desk Presets. Terminal session choices (Shell, Zellij, and zmx) belong to Terminal Board state; URLs and Vim-style Sheet Navigation settings belong to Web Board state.
- `TerminalRuntime` owns one libghostty surface and Shell, Zellij, or zmx process. One controller is used per Terminal Board.
- Each Profile has one shared `DenStorage` for persisted data, Profile-shared transient state, and live runtime registries. Profile-shared transient state includes Notifications, active drag state, Recently Removed Boards, and discarded Drawer Item restoration history. `DenStore` uses shared weak references in `DenStorage` to route Board and Desk removal invalidations to every window, so local selections and insertion anchors cannot retain removed IDs. Each Profile window has a `DenStore` for its presented Desk and application resources, and a `DenViewModel` for presentation state.
- `ProfileManager` retains each runtime's event-owner Store by Profile and Board while that runtime is active. `DenStorage` reports owner changes through a synchronous callback that captures ProfileManager weakly; it does not retain Stores. Runtime disposal removes the corresponding owner, and final Profile-window teardown releases the Profile's owners. Closing one window preserves detached runtime event delivery while other Profile windows remain.
- `DenView` renders only the Desk assigned to its window. Shared runtime storage retains both runtime types across Desk and window changes; detached Terminal views stop rendering without ending their process. A detached TerminalRuntime also runs low-frequency app ticks until its surface is visible again or the runtime is disposed; this follows [ADR 0040](./adr/0040-tick-detached-terminal-runtimes.md).
- `DenViewModel` owns Den Mode, filters, panel presentation and workflows, confirmation presentation, layout metrics, scroll and native-input requests, and Toast presentation. Each panel owns its local draft values and `FocusState`; drafts that survive panel replacement, such as Open Board input, belong to the ViewModel. Drawer Preview runtime and download operations remain in `DenStore`. Window-to-Desk assignment is managed by `ProfileManager` and is not persisted.
- zmx session discovery is window-local. Each `DenViewModel` owns one `ZmxSessionsModel`, which owns session listing, filtering, selection, deletion, and their asynchronous Tasks. The model is stopped when the zmx Sessions context closes, so late command results cannot update a closed panel. `DenStore` supplies the current zmx client and opens Boards; the ViewModel coordinates the panel transition.
- Persistence never serializes WebKit objects, terminal processes, terminal screens, or scrollback.

This boundary follows [ADR 0008](./adr/0008-codable-den-state-webview-runtime.md).

Terminal embedding and its security boundary follow [ADR 0032](./adr/0032-embed-terminal-boards-with-libghostty.md).

## Window presentation model

The Store and window presentation boundary follows [ADR 0057](./adr/0057-separate-window-presentation-from-den-store.md).

Each mounted Den window owns one `DenViewModel` in Presentation. Views, menu commands, and keyboard
routing use that same instance. The ViewModel references the window's `DenStore`; it does not copy
shared Desk or Board state. Views may read observable application state directly without a separate
ViewModel for every View.

The window ViewModel owns temporary-context transitions, drafts for its remaining panels, confirmation
display, Den/Zen/Focus modes, layout measurements, and pending scroll or native-input requests.
`OverviewViewModel`, `DrawerViewModel`, `OpenBoardViewModel`, and `DeskFilterViewModel` own their
contexts' drafts, queries, selections, local operations, and cancellable presentation Tasks.
`NotificationListViewModel` owns selection and navigation within the notification list.
The window creates and retains these models with the same Store and supplies them to their Views.
It coordinates opening, closing, transitions between contexts, and window-dependent values such as
Board width. Open Board retains its draft when returning from Zmx Sessions. Context models do not reference
one another or copy domain state. Small panels may keep their drafts in View-local State.
Models pass explicit values or identifiers to Store operations. Application-owned confirmation requests describe
the operation to confirm; Presentation owns whether the confirmation is currently displayed.

`DenStore` emits plain `DenWindowEffect` values through one synchronous callback. This preserves
multiple effects from an operation and updates input context before the next keyboard event. CLI and
IPC still call Store operations directly. Application does not depend on `DenViewModel` or its UI
state types. The window connects and disconnects the callback through its lifecycle; constructing a
ViewModel does not register callbacks.

For Board mutations that must suppress animation, Store emits a plain window effect before changing
state. The ViewModel records the request, and DenView applies the SwiftUI transaction to its rendered
window content. Application does not construct SwiftUI transactions. Tutorial operation events map to
steps in Den Application; Tutorial Domain enforces step ordering and updates progress state.

`DenFeedback` contains a message, severity, and optional Board, Drawer Item, or Notification target,
without SwiftUI styling or a presentation timer. The Store retains the latest operation feedback and
emits it as an effect. The ViewModel owns Toast display, replacement, dismissal, and its timer. A
Toast click passes the explicit target back to the Store's target-opening operation.

## Feature boundaries

### Den

Owns Den aggregate state, shared and window-local application resources, composition, and operations connecting Desks, Boards, and Drawer. `DenStore` remains one store split into focused operation extensions. `DenViewModel` owns window presentation workflows. `DenStorage` contains Profile-shared data and runtime registries. Application command payloads and Presentation workflow types are kept with their respective owners.

Desk owns Desk state and preset data. Board owns shared Board state and grouping plus its Web, Terminal, Inspection, and Tutorial implementations. Drawer owns Drawer Items, its view, and Preview runtime. Their views may depend on Den's application operations without changing data ownership. Terminal owns launch command selection and zmx query results used to prepare duplication; DenStore owns task cancellation, focus checks, Board naming against current Den state, and insertion. `ZmxSessionsModel` belongs to `Board/Terminal/Presentation` because its discovery Tasks, filtering, and selection serve the Sessions panel.

Den also owns preferences for shared presentation behavior. `IPC/Application` connects external CLI and MCP requests to active Profile windows through existing domain operations, following [ADR 0047](./adr/0047-integrate-den-cli.md) and [ADR 0055](./adr/0055-add-den-mcp-server.md).

### Overview

Overview owns its View and ViewModel under `Features/Overview/Presentation`. Its search and selection span Desks and Boards, but its selection is temporary presentation state. Den coordinates opening and closing Overview, transitions between window contexts, and the application operations that focus or rearrange Desks and Boards. Overview introduces no separate Domain layer or Store. Overview ViewModel tests belong under `Den Browser/Den BrowserTests/Overview`.

### BoardActivity

BoardActivity owns the resource-usage screen in Presentation and process sampling in Infrastructure. The screen reads shared Board state and runtimes through DenStore; Den coordinates opening, closing, and entering a Board from the screen. BoardActivity introduces no separate Domain layer, Store, or ViewModel. Sampling tests belong under `Den Browser/Den BrowserTests/BoardActivity`.

### Essentials and Notifications

Essentials owns the `Essential` model, the Prefix panel, and Essential settings. The collection remains app-wide in `AppPreferences`; the Settings scene assembles its feature-owned screen. Den coordinates Prefix presentation and opening an Essential as a Board.

Notifications owns the `DenNotification` model, list UI, and list-local selection. Notification data remains Profile-shared, transient state in `DenStorage`. DenStore records messages, marks them read, clears them, and resolves their originating Board across Desks. DenViewModel coordinates opening and closing the list, confirmation display, and transitions to other window contexts. These ownership groups do not introduce separate stores or change persistence.

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

Contains reusable operating-system integration rather than product concepts. Do not create a global Platform folder merely because code imports AppKit or WebKit. `TextInputComposition` is a feature-independent IME composition helper shared by Den, Sheet Navigation, and App settings. `SurfaceHost` is a generic native-view host shared by Board kind adapters and Drawer Preview; its API uses only AppKit views and generic request values. `WebBoardRuntime` and `WebBoardSurface` remain in `Board/Web` because they own Web Board lifecycle. `SheetNavigationManager` remains in SheetNavigation because its WebKit integration implements that Feature. `KeyboardController` remains in `App` while it routes app-wide commands into Den behavior. A component moves to `Platform` only when its API is feature-independent and no reverse dependency on a Feature is required.

## Folder rules

- Prefer feature-local files over global `Models`, `Managers`, `Utilities`, or `Views` folders.
- Use Domain, Application, Presentation, and Infrastructure within a source group only where they clarify existing responsibilities. Keep small groups flat rather than creating empty or single-file layer scaffolding.
- Promote code to `Platform` only after a feature-independent boundary genuinely exists; multiple callers alone are not sufficient.
- Keep source moves separate from behavior changes and dependency refactors.
- Keep Domain in one shared model target; split by Feature only when an independent dependency boundary exists.
- Do not edit `project.pbxproj` for ordinary moves under the file-system-synchronized root group.
- Preserve Objective-C bridging-header paths, private WebKit header references, target membership, and bundled resources during moves.

## Validation

Validation boundaries follow [testing.md](./testing.md). Swift source moves require `just check`; resource moves must additionally verify that the bundled Sheet Navigation script loads at runtime. Changes to Feature ownership or dependency direction must update a relevant ADR or add one.

Architecture decisions live in [docs/adr](./adr). Product terminology remains defined only in [CONTEXT.md](../CONTEXT.md).
