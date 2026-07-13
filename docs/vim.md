# Vim-style Sheet Navigation

Vim-style Sheet Navigation provides Vimium-like keyboard control inside the Current Sheet. It does not replace Den Mode: Sheet commands act on web content and the Sheet Stack, while Den Mode owns Desks and Boards.

The Feature is optional and disabled by default. Commands are dormant in editable controls and on Ignored Sites. `Escape` leaves an editable control or cancels a temporary mode.

## Supported commands

### Scrolling

| Keys | Action |
| --- | --- |
| `j` / `k` | Scroll down / up by 60 points. |
| `d` / `u` | Scroll down / up by half a viewport. |
| `h` / `l` | Scroll left / right by 60 points. |
| `gg` / `G` | Scroll to the top / bottom. |
| `0` / `$` | Scroll to the left / right edge. |
| `zH` / `zL` | Scroll to the left / right edge. |

A numeric prefix repeats relative scrolling commands. For example, `5j`, `3k`, and `2d` multiply their normal distance. Absolute commands ignore the prefix.

### Hints

| Keys | Action |
| --- | --- |
| `f` or `Space` | Show hints and activate a target in the Current Sheet. |
| `F` | Show link hints and open the selected link as a new Board to the right. |
| `Escape` | Cancel hints. |

`Space` remains an alias for the existing interaction. `F` only includes links with an `href`; controls that cannot sensibly open as a new Board are excluded.

### Sheet and URL navigation

| Keys | Action |
| --- | --- |
| `H` / `L` | Move backward / forward in the Sheet Stack. |
| `r` | Reload the Current Sheet. |
| `gu` | Move one level up the Current Sheet URL. |
| `gU` | Move to the Current Sheet URL root. |
| `yy` | Copy the Current Sheet URL. |

### Find

| Keys | Action |
| --- | --- |
| `/` | Open find input for the Current Sheet. |
| `n` / `N` | Repeat the last find forward / backward. |
| `Return` | Run the entered find. |
| `Escape` | Cancel find input. |

## Deliberately deferred

- `p` / `P`: opening clipboard text requires URL-versus-search behavior and pasteboard permission UX.
- `o` / `O`: an Omnibox needs a Den-native URL and search surface.
- `i`: editable focus already enters Insert state automatically.
- `v`: Visual mode needs a separate text-selection design.
- `t`, `x`, `J`, and `K`: Vimium tab operations overlap with Den's Board and Desk operations and belong in Den Mode, if added.
- bookmarks and arbitrary custom mappings: outside the first-party Feature's current scope.

## Implementation boundary

The injected script owns key sequences, counts, scrolling, hints, and find presentation. It and its native message bridge run in a dedicated `WKContentWorld`; the bridge accepts only main-frame requests while the Feature is enabled and the Sheet is not ignored. Swift owns privileged app operations: copying a URL and opening a link as a new Board. Settings and Ignored Sites apply immediately to open and future Sheets.
