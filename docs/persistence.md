# Local persistence

Den Browser persists only state needed to restore user-owned work. Version 2 adds explicit Web, Terminal, Zellij, and zmx Board content.

## Ownership

- Each Profile owns one versioned JSON `PersistedProfile` document containing `ProfileState`, `DenState`, Drawer Items, Personal Desk Presets, and Recent.
- A versioned JSON `ProfileIndex` stores Profile order.
- App-wide preferences use typed, independent `UserDefaults` keys. Retired keys may remain in `UserDefaults` and are ignored.
- WebKit owns website data in each Profile's `WKWebsiteDataStore`.
- Live Web and Terminal runtimes, `WKWebView`, Shell, Zellij, and zmx processes, terminal screens, scrollback, transient presentation state, Recently Removed Boards, and recently discarded Drawer Item restoration history are not persisted.

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
- `BoardState`: `id`, `label`, `width`, optional `customLabel`, optional `sheetNavigationPaused`, `content`
- Web Board `content`: `kind: web`, optional `currentSheetURL`, optional `firstSheetURL`
- Terminal Board `content`: `kind: terminal`, `workingDirectory`
- Zellij Board `content`: `kind: zellij`, optional `sessionName`
- zmx Board `content`: `kind: zmx`, `sessionName`
- `PersonalDeskPreset`: `id`, `label`, `boards`, optional `focusedBoardIndex`
- `DeskPresetBoard`: `label`, `width`, optional `customLabel`, and equivalent Web, Terminal, Zellij, or zmx `content`
- `RecentItem`: `kind`, plus `url` for a URL, `query` for a search term, `workingDirectory` for a Terminal location, optional `sessionName` for a Zellij session intent, or `sessionName` for a zmx session intent used by Open Board

Recent Items are recorded when a new Board is successfully opened from an input, including an Essential, an explicit link-to-new-Board action, a Drawer placement, or a zmx Session selection. Sheet navigation, Board restoration, and Drawer Preview do not create Recent Items. Opening the zmx Sessions picker without selecting a session does not create one.

A missing optional Current Sheet URL means the Board has no Current Sheet. A missing First Sheet URL means the Board cannot use the persisted First Sheet return action. Board Sheet URLs normalize HTTP(S) root paths to `/` before persistence. Absolute local file URLs are stored with the same Foundation `URL` `Codable` representation; no file contents, access bookmarks, or existence state are persisted. A moved, deleted, or machine-specific local file may therefore fail to load after restoration without invalidating the saved Board, Drawer Item, Recent Item, or Desk Preset.

Version 1 documents decode as Web Boards and are written back as version 2. An ordinary Terminal Board restores a new Shell in the saved Working Directory. Named Zellij restoration runs `zellij attach --create <sessionName>`; an unnamed Zellij Board runs `zellij -l welcome`. zmx restoration runs `zmx attach <sessionName>`.

## App preference keys

- App-wide `UserDefaults` keys use `preferences.<domain>.<setting>` or
  `preferences.<domain>.<setting>.<property>`. Domains describe stable preference
  ownership rather than Settings tab placement. Key components use kebab-case.

| Domain | Setting | Key | Stored value | Default | Settings location |
| --- | --- | --- | --- | --- | --- |
| `schema` | Version | `preferences.schema.version` | `Int` | `1` | Internal |
| `sheet-navigation` | Enabled | `preferences.sheet-navigation.enabled` | `Bool` | `false` | Web > Vim-style Sheet Navigation |
| `sheet-navigation` | Hint alphabet | `preferences.sheet-navigation.hint-alphabet` | `String` | `asdfghjkl` | Web > Vim-style Sheet Navigation |
| `sheet-navigation` | Ignored hosts | `preferences.sheet-navigation.ignored-hosts` | `[String]` | `[]` | Web > Vim-style Sheet Navigation |
| `shortcuts` | Action override | `preferences.shortcuts.actions.<action-id>` | Property-list encoded `ShortcutOverride` | Absent; uses the action default | Shortcuts > Shortcuts |
| `shortcuts` | Desk number binding | `preferences.shortcuts.desk-number.binding` | Property-list encoded `ShortcutBinding` | `Command` + `Option` + digit | Shortcuts > Focus Desk 1–10 |
| `shortcuts` | Desk number disabled | `preferences.shortcuts.desk-number.disabled` | `Bool` | Absent / `false` | Shortcuts > Focus Desk 1–10 |
| `appearance` | Motion mode | `preferences.appearance.motion.mode` | `MotionPreference.rawValue` | `follow-system` | Appearance > Motion |
| `appearance` | Board centering mode | `preferences.appearance.board-centering.mode` | `FocusedBoardCentering.rawValue` | `never` | Appearance > Board Centering |
| `appearance` | Sheet scale | `preferences.appearance.sheet-scale.percent` | `Int` (`50...200`) | `100` | Appearance > Sheet Scale |
| `content-blocking` | uBlock Origin Lite enabled | `preferences.content-blocking.ubolite.enabled` | `Bool` | `false` | Web > Content Blocking |
| `terminal` | Zellij executable path | `preferences.terminal.zellij.executable-path` | `String` | Empty | Terminal > Zellij |
| `terminal` | zmx executable path | `preferences.terminal.zmx.executable-path` | `String` | Empty | Terminal > zmx |
| `essentials` | Items | `preferences.essentials.items` | Property-list encoded `[Essential]` | Absent | Essentials |

`BoardState.sheetNavigationPaused` stores whether Vim-style Sheet Navigation is
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
- Breaking changes require a new schema version and an explicit migration before writing the new format.
- Version 1 fixtures in `Den Browser/Den BrowserTests/Fixtures` are the executable format contract.

Unreadable Profile documents and indexes are preserved with a `.corrupt-<timestamp>` suffix before recovery continues.
