---
status: accepted
---

# Use Den Mode for sheet-independent keyboard control

Den Browser uses persistent Den Mode instead of the shared `Control` + `Option` prefix. This supersedes that shortcut-prefix decision in ADR 0003.

- `Control` + `,` is the default Den Mode Toggle. It switches symmetrically between Sheet Input and Den Mode.
- Escape exits Den Mode to Sheet Input. In nested temporary states, Escape closes one level at a time before returning to Sheet Input.
- Zellij's unlock-first model informs the symmetric toggle, but compatibility with Zellij's toggle key is not a shortcut-selection requirement. The Den Mode Toggle must be justified by Den's own ergonomics and conflicts.
- The default Den Mode Toggle must require little movement from a normal typing posture on US ANSI, JIS, and ISO QWERTY layouts. One-handed use is not required when a split-hand chord is equally or more comfortable. The binding is expected to become configurable so Dvorak, Colemak, custom layouts, and site-specific conflicts do not force a change to the default.
- The default uses a conventional simultaneous chord of one modifier and one primary key. Single unmodified keys, timed modifier taps, long presses, sequential prefixes, and function keys are rejected because they steal Sheet Input, introduce timing behavior, add keystrokes, or depend on keyboard settings.
- The default must not consume a chord that produces text or begins dead-key composition in Sheet Input. This rules out `Option` plus an alphabetic or punctuation key because Option participates in macOS text entry and varies by input source. `Control` remains the preferred modifier despite its smaller shortcut namespace because it does not serve as a printable-character modifier.
- The default does not use a digit. Digits denote Desk positions in Den Mode, so reusing one for the input-context boundary would give it two unrelated meanings. Future shortcut customization may still permit digit bindings.
- The default must preserve established, frequent shortcuts in first-class Sheet workloads such as web terminals, browser IDEs, and spreadsheets. This rules out mnemonic choices such as `Control` + `D`, which carries EOF, forward-delete, and Vim scrolling behavior, and `Control` + semicolon, which inserts the current date in Excel. Future customization may still permit these bindings.
- `Control` + `,` won the final comparison with `Control` + `.` because the comma uses the stronger middle finger from the typing posture and avoids `Control` + `.` operations in Excel and PowerPoint for the web. Its resemblance to the standard `Command` + `,` Settings shortcut is accepted because the modifier and action remain distinct.
- Den Mode captures every following key, including undefined keys. Entering it during an IME composition does not preserve that composition.
- The titlebar shows Den Mode and, when applicable, Cut Board state. A cyan Den outer ring is a secondary visual signal; no mode overlay covers boards or sheets.
- `o` opens Overview, a temporary screen within Den Mode. Its Escape returns to Den Mode; a second Escape returns to Sheet Input.
- Overview accepts only movement, Shift plus movement, Return, and Escape. Movement changes the Overview Selection; Return makes it the Focused Board.
- `n` opens a new board and Shift plus `n` opens a new desk. `Command` + `T` also opens the Open Board panel from every keyboard context, including Den Mode and Overview. Their panels suspend Den Mode. Creating the Board or Desk returns to Sheet Input; canceling returns to Den Mode.
- Left and right arrows, or `h` and `l`, navigate boards. Up and down arrows, or `j` and `k`, navigate desks. Shift plus either movement key moves the focused board in that direction.
- `-` narrows the focused board and `=` widens it. Shift is meaningful for board movement only with a movement key.
- `[` and `]` move backward and forward in the focused board's sheet stack. Reload remains `Command` + `r` outside Den Mode.
- Return duplicates the Focused Board's Current Sheet to a new board on its right, focuses it, and returns to Sheet Input.
- A Den has at most ten desks. `1` through `9` focus desks one through nine, and `0` focuses desk ten. A missing desk is a no-op.
- Shift plus a digit moves the focused board to that desk, immediately after its focused board, then focuses the moved board.
- `x` cuts a focused board into the sole Cut Board slot without closing its live sheet runtime. `p` places it to the right of the focused board; `u` restores it to its former placement. While a Cut Board exists, `x` does nothing.
- `d` permanently closes the focused board without site-provided close confirmation. Supporting `beforeunload` is outside the MVP and requires a separate proof of concept.
- Shift plus `d` deletes the focused desk only when it is empty and another desk remains.
- Navigation, layout, cut, placement, restoration, and close operations keep Den Mode active. Creating a board or desk, or duplicating a Current Sheet, returns to Sheet Input.
