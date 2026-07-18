# Local persistence

Den Browser persists only state needed to restore user-owned work. Version 1 is the first public local format. Prerelease formats are not supported.

## Ownership

- Each Profile owns one versioned JSON `PersistedProfile` document containing `ProfileState`, `DenState`, and Personal Desk Presets.
- A versioned JSON `ProfileIndex` stores Profile order.
- App-wide preferences use typed, independent `UserDefaults` keys.
- WebKit owns website data in each Profile's `WKWebsiteDataStore`.
- Live `BoardRuntime`, `WKWebView`, presentation state, and the Recently Removed Board are not persisted.

## Version 1 JSON keys

`ProfileIndex`:

- `schemaVersion`
- `profileIDs`

`PersistedProfile`:

- `schemaVersion`
- `profile`
- `den`
- `deskPresets`

Nested objects use these keys:

- `ProfileState`: `id`, `name`, `color`, `webProfileStore`
- `WebProfileStore`: `kind`, optional `identifier`
- `DenState`: `desks`, `focusedDeskID`
- `DeskState`: `id`, `label`, `boards`, optional `focusedBoardID`
- `BoardState`: `id`, `label`, `width`, optional `currentSheetURL`
- `PersonalDeskPreset`: `id`, `label`, `boards`, optional `focusedBoardIndex`
- `DeskPresetBoard`: `label`, `width`, optional `initialSheetURL`

A missing optional Sheet URL means the Board has no Sheet. URLs encode using Foundation `URL`'s `Codable` representation.

## App preference keys

- `preferences.schemaVersion`
- `features.vim-style-sheet-navigation.enabled`
- `features.vim-style-sheet-navigation.hint-alphabet`
- `features.vim-style-sheet-navigation.ignored-hosts`
- `shortcuts.<ShortcutAction raw value>`
- `appearance.motion`

The absence of `preferences.schemaVersion` means version 0. Preferences migrate one version at a time, preserve existing per-key values when adopting version 1, and update the version key only after each migration step completes. A schema version newer than the app supports is not overwritten or downgraded.

## Compatibility rules

- Existing keys and enum raw values are never renamed or removed within version 1.
- Existing keys do not change meaning or encoded type within version 1.
- New fields must be optional or decode with a default when absent.
- Decoders ignore unknown keys so newer additive documents remain readable.
- Breaking changes require a new schema version and an explicit migration before writing the new format.
- Version 1 fixtures in `Den Browser/Den BrowserTests/Fixtures` are the executable format contract.

Unreadable Profile documents and indexes are preserved with a `.corrupt-<timestamp>` suffix before recovery continues.
