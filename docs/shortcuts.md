# Den Browser Shortcuts

Den-owned shortcuts use `Control` + `Option` as the shared prefix. `Command` shortcuts are left to macOS and conventional app-level behavior.

| Shortcut | Action | Notes |
| --- | --- | --- |
| `Control` + `Option` + `N` | New Desk panel | Creates a labeled desk from an Empty or built-in template. |
| `Control` + `Option` + Space | Open Board panel | Creates a board from URL or search text. |
| `Control` + `Option` + `O` | Toggle overview | Shows or hides the lightweight desk and board map. |
| `Control` + `Option` + Left | Previous board | Moves focus. Used to choose placement target while holding. |
| `Control` + `Option` + Right | Next board | Moves focus. Used to choose placement target while holding. |
| `Control` + `Option` + Up | Previous desk | Moves focus. Used to choose placement target while holding. |
| `Control` + `Option` + Down | Next desk | Moves focus. Used to choose placement target while holding. |
| `Control` + `Option` + Shift + Left | Move board left | Swaps the focused board left in the current desk. |
| `Control` + `Option` + Shift + Right | Move board right | Swaps the focused board right in the current desk. |
| `Control` + `Option` + Shift + Up | Move board to previous desk | Moves the focused board to another desk. |
| `Control` + `Option` + Shift + Down | Move board to next desk | Moves the focused board to another desk. |
| `Control` + `Option` + `[` | Back in sheet stack | Uses the focused board. |
| `Control` + `Option` + `]` | Forward in sheet stack | Uses the focused board. |
| `Control` + `Option` + `-` | Narrow board | Adjusts focused board width. |
| `Control` + `Option` + `;` | Widen board | Adjusts focused board width. |
| `Control` + `Option` + `W` | Close board | Closes the focused board. |
| `Control` + `Option` + Return | Duplicate current sheet | Creates a new board to the right using the focused board's current sheet URL. |
| `Control` + `Option` + `H` | Hold board | Picks up the focused board for placement. |
| `Control` + `Option` + `P` | Place held board | Places the held board to the right of the focused board. |
| Escape | Cancel board hold / dismiss panel | Clears the held-board reference without reverting other Den changes. |

Reserved:

- `Control` + `Option` + `Q` is unused. `Q` implies quitting a larger scope such as a desk or the app.

## Overview

While overview is open, Den uses unprefixed movement keys because web content is not active. Movement changes the overview selection. Return commits the overview selection as the focused board; Escape closes overview without changing focus.

| Shortcut | Action |
| --- | --- |
| Left / Right | Move overview selection between boards |
| Up / Down | Move overview selection between desks |
| Shift + Left / Right | Move the selected board within the current desk |
| Shift + Up / Down | Move the selected board to another desk |
| Return | Enter the selected board |
| Escape | Close overview and keep the previous focus |
