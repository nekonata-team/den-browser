---
status: accepted
---

# Preserve entrenched browser shortcuts selectively

Den Browser preserves browser and app shortcuts whose muscle memory is strong enough to outweigh the distinction between browser concepts and Den concepts. `Command` + `T` opens the Open Board panel in every keyboard context, `Command` + `R` reloads the Current Sheet outside Den Mode, and `Command` + `Q` exits the app from every keyboard context. App termination restores any Held Board before exit. This supersedes ADR 0003's blanket avoidance of `Command`-based browser compatibility shortcuts and its explicit omission of `Command` + `T`.

This is not a general mapping from conventional browser features to Den Browser. Each shortcut must still fit Den's domain model and interaction semantics; `Command` + `T` creates a Board in the established placement, while `Command` + `R` acts on the Current Sheet.

`Command` + `Option` + Left or Right Arrow navigates to the previous or next Board without entering Den Mode, following [Chrome's established macOS shortcuts](https://support.google.com/chrome/answer/157179) for moving between neighboring browser contexts. Adding Shift moves the Focused Board left or right instead, matching Den Mode's rule that Shift turns focus movement into Board movement. These shortcuts are available from Sheet Input and Den Mode, but not while Overview or a creation panel is open.

`Option` plus arrows was rejected as the direct shortcut family because it would take macOS text navigation from Sheets and collide with operations in Google Sheets and web editors. `Command` + `Option` + Up or Down Arrow was also rejected: Desk Navigation is less frequent than Board Navigation, no established browser shortcut justifies taking those keys, and web editors such as VS Code use them for multiple cursors. Den therefore owns only the horizontal `Command` + `Option` arrow family outside Den Mode.
