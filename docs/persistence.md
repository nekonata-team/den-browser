# Local persistence

Den Browser persists only state needed to restore user-owned work. Version 3 groups Board data by Board kind and stores terminal session configuration under Terminal Board state.

## Ownership

- Each Profile owns one versioned JSON `PersistedProfile` document containing `ProfileState`, `DenState`, Drawer Items, Personal Desk Presets, and Recent.
- A versioned JSON `ProfileIndex` stores Profile order.
- App-wide preferences use typed, independent `UserDefaults` keys. Retired keys may remain in `UserDefaults` and are ignored.
- Profile windows use the SwiftUI scene identifier `profile-window`.
  Private Den disables scene restoration so routes from previous sessions cannot claim its Desks.
  Ordinary Profile windows retain automatic scene restoration.
  At startup, legacy SwiftUI window frame and split-view keys are removed individually from defaults.
  These keys contained reflected view types and addresses that caused unbounded growth, while bulk deletion could exceed CFPreferences request limits.
  Old positions and split widths are discarded, but preferences and Profile documents are preserved.
  Tests and benchmark launches skip this cleanup.
- WebKit owns website data in each Profile's `WKWebsiteDataStore`.
- uBlock Origin Lite resources and enabled preferences persist app-wide.
  Ordinary Profiles use a persistent WebKit extension controller, while Private Den uses a non-persistent one that discards session state.
  Only inactive Profiles with no open windows can be deleted.
  Settings disables deletion while windows are open, and deletion verifies this before touching data.
  During deletion, that Profile cannot open windows, create controllers, or start another deletion.
  If deletion fails, those operations become available again.
  Deleting an eligible Profile releases its resources and removes its dedicated `~/Library/WebKit/<bundle-id>/WebExtensions/<profile-id>/` directory, including settings and compiled content-blocking rules.
  The directory is keyed by Profile ID independently of the website data store ID.
  A cleanup error reports Profile deletion failure and retains the Profile document for retry; website data may already have been removed.
  Den does not scan or remove orphaned extension directories from earlier versions.
- Tutorial Boards and checklist progress are session-only and omitted from Profile JSON.
  A Desk whose only Board was a Tutorial Board restores empty.
- Ordinary Profiles save Board Facings as disposable PNG files under `~/Library/Caches/<bundle-id>/BoardFacings/<profile-id>/`.
  Private Den never writes Board Facings to disk.
  Overview loads cached Facings asynchronously without opening Boards, capped at 64 MiB memory and 128 MiB disk per Profile.
  Deleted Board images remain available for same-session restoration, and unused files are pruned when resources reinitialize.
  Clearing browsing data or deleting a Profile removes its Facings; missing or corrupt files are simple cache misses.
- Ephemeral runtime state is not persisted.
  This includes Web and Terminal runtimes, WebView and shell processes, scrollback, Recently Removed Boards, and discarded Drawer history.

## Version 3 JSON keys

`BoardState.kind` and `DeskPresetBoard.kind` retain the JSON key `content` for version 3 compatibility. This is a storage key, not a separate domain concept; the schema and migrations remain unchanged.

`ProfileIndex`:

- `schemaVersion`
- `profileIDs`

`PersistedProfile`:

- `schemaVersion`
- `profile`
- `den`
- `deskPresets`
- optional `recentItems`

Nested objects use these keys:

- `ProfileState`: `id`, `name`, `color` (a preset name or custom sRGB components), `webProfileStore`
- `WebProfileStore`: `kind`, optional `identifier`
- `DenState`: `desks`, `focusedDeskID`, optional `drawerItems`
- `DrawerItem`: `id`, `url`, optional `title`
- `DeskState`: `id`, `label`, `boards`, optional `focusedBoardID`
- `BoardState`: `id`, `label`, `width`, `role`, `content`, optional `customLabel`
- `BoardRole`: `kind: primary`, or `kind: sideBoard` with `targetBoardID`
- Web Board `content`: `kind: web`, optional `currentSheetURL`, optional `firstSheetURL`, optional `sheetNavigationPaused`
- Inspection Board `content`: `kind: inspection`
- Terminal Board `content`: `kind: terminal`, `session`
- Shell session: `kind: shell`, `workingDirectory`
- Zellij session: `kind: zellij`, optional `sessionName`
- zmx session: `kind: zmx`, `sessionName`, `workingDirectory`, optional `rootSessionName`
- `PersonalDeskPreset`: `id`, `label`, `boards`, optional `focusedBoardIndex`
- `DeskPresetBoard`: `label`, `width`, optional `customLabel`, `content` using Web, Inspection, or Terminal with a Shell, Zellij, or zmx `session`, and optional `targetBoardIndex` for a Side Board (Inspection or Terminal) pointing to its Primary Board. A zmx session may include `rootSessionName` when its group is known.
- `RecentItem`: `kind`, plus `url` for a URL, `query` for search, `workingDirectory` for Terminal,
  optional `sessionName` for Zellij, or `sessionName` for zmx Open Board intent

Recent Items are recorded when a new Board opens from an input, such as an Essential,
a link-to-new-Board action, a Drawer placement, or a selected zmx Session.
Sheet navigation, Board restoration, Drawer Peek, and unconfirmed picker selections do not create Recent Items.
Removing an item or clearing Recent immediately saves the Profile document, restoring the in-memory list if saving fails.

A Web Board without an optional Current Sheet URL simply has no Current Sheet,
while a missing First Sheet URL disables returning to the initial Sheet.
Web Board URLs normalize HTTP(S) root paths to `/` before persistence.
Local file URLs persist as standard Foundation `URL`s without saving contents, bookmarks, or verifying file existence.
Consequently, a moved or missing local file fails to load upon restoration without invalidating saved models.

`PersistedProfileDocumentDecoder` migrates version 1 and 2 documents before decoding:
- Version 1 Boards decode as Web Boards.
- Version 2 flat kinds (`terminal`, `zellij`, `zmx`) and legacy Desk Presets normalize to version 3 in memory.
- `sheetNavigationPaused` moves into Web Board content.
- Terminal Boards restore a new Shell in the saved Working Directory.
- Named Zellij attaches via `zellij attach --create <sessionName>`; unnamed Zellij runs `zellij -l welcome`.
- zmx restoration attaches via `zmx attach <sessionName>`.

When `BoardState.role` is absent, it decodes as `primary`.

## App preference keys

- App-wide `UserDefaults` keys use `preferences.<domain>.<setting>` or
  `preferences.<domain>.<setting>.<property>`. Domains describe stable preference
  ownership rather than Settings tab placement. Key components use kebab-case.

| Domain | Setting | Key | Stored value | Default | Settings location |
| --- | --- | --- | --- | --- | --- |
| `schema` | Version | `preferences.schema.version` | `Int` | `1` | Internal |
| `search` | Engine | `preferences.search.engine` | `SearchEngine.rawValue` | `google` | Web > Search |
| `external-links` | Destination | `preferences.external-links.destination` | `ExternalLinkDestination.rawValue` | `drawer-peek` | Web > Sheet Navigation |
| `sheet-navigation` | Enabled | `preferences.sheet-navigation.enabled` | `Bool` | `false` | Web > Vim-style Sheet Navigation |
| `sheet-navigation` | Hint alphabet | `preferences.sheet-navigation.hint-alphabet` | `String` | `asdfghjkl` | Web > Vim-style Sheet Navigation |
| `sheet-navigation` | Ignored hosts | `preferences.sheet-navigation.ignored-hosts` | `[String]` | `[]` | Web > Vim-style Sheet Navigation |
| `picture-in-picture` | Automatic Desk switch | `preferences.picture-in-picture.auto-on-desk-switch` | `Bool` | `false` | Web > Picture in Picture |
| `shortcuts` | Action override | `preferences.shortcuts.actions.<action-id>` | Property-list encoded `ShortcutOverride` | Absent; uses the action default | Shortcuts > Shortcuts |
| `shortcuts` | Desk number binding | `preferences.shortcuts.desk-number.binding` | Property-list encoded `ShortcutBinding` | `Command` + `Option` + digit | Shortcuts > Focus Desk 1–10 |
| `shortcuts` | Desk number disabled | `preferences.shortcuts.desk-number.disabled` | `Bool` | Absent / `false` | Shortcuts > Focus Desk 1–10 |
| `appearance` | Motion mode | `preferences.appearance.motion.mode` | `MotionPreference.rawValue` | `follow-system` | Appearance > Motion |
| `appearance` | Desk switcher alignment | `preferences.appearance.desk-switcher.alignment` | `DeskSwitcherAlignment.rawValue` (`left`, `center`) | `left` | Appearance > Desk Switcher |
| `appearance` | Board centering mode | `preferences.appearance.board-centering.mode` | `FocusedBoardCentering.rawValue` | `on-overflow` | Appearance > Board Centering |
| `appearance` | Board Rail visibility | `preferences.appearance.board-rail-presented` | `Bool` | `false`; shared across windows and restored at launch | Board Rail |
| `appearance` | Sheet scale | `preferences.appearance.sheet-scale.percent` | `Int` (`50...200`) | `100` | Appearance > Sheet Scale |
| `drawer` | Style | `preferences.drawer.style` | `DrawerStyle.rawValue` | `floating` | Appearance > Drawer |
| `content-blocking` | uBlock Origin Lite enabled | `preferences.content-blocking.ubolite.enabled` | `Bool` | `false` | Web > Content Blocking |
| `terminal` | Zellij executable path | `preferences.terminal.zellij.executable-path` | `String` | Empty | Terminal > Zellij |
| `terminal` | zmx executable path | `preferences.terminal.zmx.executable-path` | `String` | Empty | Terminal > zmx |
| `essentials` | Items | `preferences.essentials.items` | Property-list encoded `[Essential]` | Absent | Essentials |

Web Board state's `sheetNavigationPaused` stores whether Vim-style Sheet Navigation is
paused for that Board. It defaults to `false` when absent, follows the Board
through Desk moves and restoration, and is copied when a Web Board is duplicated.

The absence of `preferences.schema.version` means version 0. Preferences migrate one
version at a time and update the version key only after each migration step
completes. Missing values use their defaults. A schema version newer than the app
supports is not overwritten or downgraded.

## Compatibility rules

- Existing preference keys and enum raw values are not renamed or removed within a
  released schema version.
- Existing preference keys do not change meaning or encoded type within a released
  schema version.
- New fields must be optional or decode with a default when absent.
- Decoders ignore unknown keys so newer additive documents remain readable.
- A supported release must read data written by earlier supported releases. Downgrades
  are not supported.
- Schema versions are bumped only for breaking persistence changes.
- Breaking changes require a new schema version and an explicit migration before writing the new format.
- Version 1 and 2 fixtures in `Den Browser/Den BrowserTests/Fixtures` are the executable format contract.

Confirmed-invalid Profile documents and indexes are preserved with a `.corrupt-<timestamp>` suffix before recovery continues.
Read failures and unsupported schema versions are reported and kept in place; they are not treated as corruption or
silently replaced. If a confirmed-invalid file cannot be quarantined, recovery does not rewrite the Profile index.

## Persistence failure and recovery contract

- Profile document saves use atomic file writes.
- Save failures appear as error Toasts in open Den windows and remain available in the Settings Profile Error alert.
  Failed deferred saves end without retaining a retry; the next successful normal save includes the latest in-memory state.
- Focus changes and keyboard Board Width adjustments coalesce per Profile, saving 300 ms after the latest change.
  Immediate Profile saves include the latest Den state and cancel pending deferred saves.
- Normal app termination synchronously flushes pending deferred saves, using the last stable snapshot if a drag is active.
  An abrupt termination before 300 ms of inactivity can lose recent unsaved adjustments.
- `ProfileManager` maintains the latest intended `PersistedProfile` document in memory.
  If disk writing fails, it reports the error and returns `false` without rolling back the cache.
  This prevents subsequent saves of other collections (such as Recent Items or Desk Presets) from overwriting disk with outdated state.
- Irreversible operations (such as closing a live Board) retain intended state in UI and memory rather than artificially rewinding.
- Failed Recent persistence restores the previous Recent collection; a Board created by that operation remains created.
- UI operations report success (such as displaying a success Toast) only after disk persistence succeeds.
