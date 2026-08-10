# Local persistence

Den Browser persists only state needed to restore user-owned work. Version 2 adds explicit Web, Terminal, and Zellij Board content.

## Ownership

- Each Profile owns one versioned JSON `PersistedProfile` document containing `ProfileState`, `DenState`, Drawer Items, Personal Desk Presets, and Recent.
- A versioned JSON `ProfileIndex` stores Profile order.
- App-wide preferences use typed, independent `UserDefaults` keys.
- WebKit owns website data in each Profile's `WKWebsiteDataStore`.
- Live Web and Terminal runtimes, `WKWebView`, Shell and Zellij processes, terminal screens, scrollback, transient presentation state, and the Recently Removed Board are not persisted.

## Version 2 JSON keys

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

- `ProfileState`: `id`, `name`, `color`, `webProfileStore`
- `WebProfileStore`: `kind`, optional `identifier`
- `DenState`: `desks`, `focusedDeskID`, optional `drawerItems`, optional `expandedDrawerItemID`
- `DrawerItem`: `id`, `url`, optional `title`
- `DeskState`: `id`, `label`, `boards`, optional `focusedBoardID`
- `BoardState`: `id`, `label`, `width`, optional `customLabel`, `content`
- Web Board `content`: `kind: web`, optional `currentSheetURL`, optional `firstSheetURL`
- Terminal Board `content`: `kind: terminal`, `workingDirectory`
- Zellij Board `content`: `kind: zellij`, optional `sessionName`
- `PersonalDeskPreset`: `id`, `label`, `boards`, optional `focusedBoardIndex`
- `DeskPresetBoard`: `label`, `width`, optional `customLabel`, and equivalent Web, Terminal, or Zellij `content`
- `RecentItem`: `kind`, plus `url` for a URL, `query` for a search term, `workingDirectory` for a Terminal location, or optional `sessionName` for a Zellij session intent used by Open Board

A missing optional Current Sheet URL means the Board has no Current Sheet. A missing First Sheet URL means the Board cannot use the persisted First Sheet return action. Board Sheet URLs normalize HTTP(S) root paths to `/` before persistence. Absolute local file URLs are stored with the same Foundation `URL` `Codable` representation; no file contents, access bookmarks, or existence state are persisted. A moved, deleted, or machine-specific local file may therefore fail to load after restoration without invalidating the saved Board, Drawer Item, Recent Item, or Desk Preset.

Version 1 documents decode as Web Boards and are written back as version 2. An ordinary Terminal Board restores a new Shell in the saved Working Directory. Named Zellij restoration runs `zellij attach --create <sessionName>`; an unnamed Zellij Board runs `zellij -l welcome`.

## App preference keys

- `preferences.schemaVersion`
- `features.vim-style-sheet-navigation.enabled`
- `features.vim-style-sheet-navigation.hint-alphabet`
- `features.vim-style-sheet-navigation.ignored-hosts`
- `shortcuts.<ConfigurableShortcut raw value>`
- `shortcuts.desk-number`, optional `shortcuts.desk-number.disabled`
- `appearance.motion`
- `appearance.board-centering`
- `appearance.sheet-scale`
- `features.native-picture-in-picture.enabled`

The absence of `preferences.schemaVersion` means version 0. Preferences migrate one version at a time, preserve existing per-key values when adopting version 1, and update the version key only after each migration step completes. A schema version newer than the app supports is not overwritten or downgraded.

## Compatibility rules

- Existing keys and enum raw values are never renamed or removed within version 1.
- Existing keys do not change meaning or encoded type within version 1.
- New fields must be optional or decode with a default when absent.
- Decoders ignore unknown keys so newer additive documents remain readable.
- Breaking changes require a new schema version and an explicit migration before writing the new format.
- Version 1 fixtures in `Den Browser/Den BrowserTests/Fixtures` are the executable format contract.

Unreadable Profile documents and indexes are preserved with a `.corrupt-<timestamp>` suffix before recovery continues.
