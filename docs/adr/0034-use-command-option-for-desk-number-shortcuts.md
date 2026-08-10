---
status: accepted
---

# Use Command-Option for numbered Desk shortcuts

Den Browser uses `Command` + `Option` plus a digit as the default shortcut family for focusing Desks 1 through 10 from Sheet Input. The `0` digit still selects Desk 10, preserving the direct ten-position mapping, but `Command` + `0` remains available to the focused Sheet and Terminal Board.

The earlier `Command`-only default followed browser tab-selection muscle memory, but it also claimed `Command` + `0`, an established zoom-reset shortcut in web content and a font-size-reset shortcut in embedded Ghostty. Den hosts both kinds of content, so an app-wide `Command`-only binding would consume a meaningful content shortcut before it could reach the focused Board.

The additional `Option` modifier avoids that collision without inventing a special key for Desk 10 or removing direct access to any numbered Desk. The Desk-number preference remains one configurable modifier combination shared by the ten logical digit keys. Existing custom bindings and explicit unassignment are preserved; changing the default affects users without a stored override and the Reset action.

This supersedes the default modifier choice described in [ADR 0011](./0011-preserve-entrenched-browser-shortcuts.md) and [ADR 0016](./0016-customize-sheet-independent-den-shortcuts-as-logical-keys.md). It does not change the maximum Desk count, Den Mode's fixed digit commands, or the customization model.
