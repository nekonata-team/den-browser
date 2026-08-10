---
status: accepted
---

# Preserve entrenched browser shortcuts selectively

Den Browser preserves browser and app shortcuts whose muscle memory is strong enough to outweigh the distinction between browser concepts and Den concepts. `Command` + `T` opens the Open Board panel in every keyboard context, `Command` + `L` opens the Edit Focused Board Link panel and replaces its Current Sheet on confirmation, `Command` + `R` reloads the Current Sheet outside Den Mode, and `Command` + `Q` exits the app from every keyboard context. This supersedes ADR 0003's blanket avoidance of `Command`-based browser compatibility shortcuts and its explicit omission of `Command` + `T`.

This is not a general mapping from conventional browser features to Den Browser. Each shortcut must still fit Den's domain model and interaction semantics; `Command` + `T` creates a Board in the established placement, `Command` + `L` replaces the Current Sheet in the Focused Board, and `Command` + `R` acts on the Current Sheet.

`Command` + `W` removes the Focused Board in every keyboard context, preserving the entrenched browser action of dismissing the current browsing context without calling a Board a tab. Because macOS normally uses that shortcut to close a window, `Shift` + `Command` + `W` explicitly closes the current Profile window. Other windows, including Settings, retain the standard `Command` + `W` behavior.

`Command`-clicking a supported Sheet link in a Current Sheet creates an adjacent Board without changing the Focused Board. Adding Shift focuses the new Board. This preserves the established macOS browser distinction between opening a background browsing context and opening one for immediate use while expressing both outcomes as Board placement. Option-click is reserved for Den's distinct Drawer capture operation rather than Board creation. Supported Sheet links include HTTP, HTTPS, and local file URLs per [ADR 0033](./0033-support-local-file-sheet-urls.md).

`Command` + `Option` + Left or Right Arrow navigates to the previous or next Board without entering Den Mode, following [Chrome's established macOS shortcuts](https://support.google.com/chrome/answer/157179) for moving between neighboring browser contexts. Adding Shift moves the Focused Board left or right instead, matching Den Mode's rule that Shift turns focus movement into Board movement. These shortcuts are available from Sheet Input and Den Mode, but not while Overview or a creation panel is open.

`Command` + `Option` + `1` through `9`, and `Command` + `Option` + `0`, focus Desk 1 through 10 from Sheet Input. This keeps direct numbered Desk selection and the familiar ten-position sequence while leaving `Command` + `0` available to Sheet and Terminal Board content as an established zoom or font-size reset. The modifier choice supersedes the earlier `Command`-only default; see [ADR 0034](./0034-use-command-option-for-desk-number-shortcuts.md).

`Option` plus arrows was rejected as the direct shortcut family because it would take macOS text navigation from Sheets and collide with operations in Google Sheets and web editors. `Command` + `Option` + Up or Down Arrow was also rejected: Desk Navigation is less frequent than Board Navigation, no established browser shortcut justifies taking those keys, and web editors such as VS Code use them for multiple cursors. Den therefore owns only the horizontal `Command` + `Option` arrow family outside Den Mode.
