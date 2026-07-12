---
status: accepted
---

# Use Den Mode for sheet-independent keyboard control

Den Browser uses persistent Den Mode instead of the shared `Control` + `Option` prefix. This supersedes that shortcut-prefix decision in ADR 0003.

- `Control` + `.` enters Den Mode. Escape exits it to sheet input.
- Den Mode captures every following key, including undefined keys. Entering it during an IME composition does not preserve that composition.
- The titlebar shows Den Mode and, when applicable, Cut Board state. A cyan Den outer ring is a secondary visual signal; no mode overlay covers boards or sheets.
- `o` opens Overview, a temporary screen within Den Mode. Its Escape returns to Den Mode; a second Escape returns to sheet input.
- Overview accepts only movement, Shift plus movement, Return, and Escape. Movement changes the Overview Selection; Return makes it the Focused Board.
- `n` opens a new board and Shift plus `n` opens a new desk. Their panels suspend Den Mode. Creating the Board or Desk returns to sheet input; canceling returns to Den Mode.
- Left and right arrows, or `h` and `l`, navigate boards. Up and down arrows, or `j` and `k`, navigate desks. Shift plus either movement key moves the focused board in that direction.
- `-` narrows the focused board and `=` widens it. Shift is meaningful for board movement only with a movement key.
- `[` and `]` move backward and forward in the focused board's sheet stack. Reload remains `Command` + `r` outside Den Mode.
- Return duplicates the focused board's current sheet to a new board on its right, focuses it, and returns to sheet input.
- A Den has at most ten desks. `1` through `9` focus desks one through nine, and `0` focuses desk ten. A missing desk is a no-op.
- Shift plus a digit moves the focused board to that desk, immediately after its focused board, then focuses the moved board.
- `x` cuts a focused board into the sole Cut Board slot without closing its live sheet runtime. `p` places it to the right of the focused board; `u` restores it to its former placement. While a Cut Board exists, `x` does nothing.
- `d` permanently closes the focused board without site-provided close confirmation. Supporting `beforeunload` is outside the MVP and requires a separate proof of concept.
- Shift plus `d` deletes the focused desk only when it is empty and another desk remains.
- Navigation, layout, cut, placement, restoration, and close operations keep Den Mode active. Creating a board or desk, or duplicating a current sheet, returns to sheet input.
