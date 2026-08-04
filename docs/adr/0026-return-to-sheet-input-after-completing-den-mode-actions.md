---
status: accepted
---

# Return to Sheet Input after completing Den Mode actions

> Repeatable Den operations keep Den Mode active. Successful confirmation or completion returns to Sheet Input. Canceling returns to the originating input context. Invalid or failed operations preserve the current input context.

This decision updates the operation-specific mode transitions in [ADR 0009](./0009-den-mode-for-sheet-independent-keyboard-control.md) without replacing Den Mode. The interaction expresses intent: relative movement supports continued exploration, while direct selection confirms a destination. Board Removal remains part of an organizing workflow, while saving a Desk Preset completes a standalone task.

## Success and cancellation

1. Escape and the Den Mode Toggle return from Den Mode to Sheet Input.
2. Canceling a temporary context returns to its originating input context.
3. Invalid, unavailable, or failed operations do not change the input context.
4. A valid direct selection succeeds even when its target is already focused.
5. A modifying operation succeeds only when it performs its intended mutation. Moving the Focused Board to its current Desk therefore fails and keeps Den Mode active.
6. A valid confirmation succeeds even when its value is unchanged. Validation failure keeps its panel open.

## Keep Den Mode active

Exploration:

- Relative Board Navigation with Left and Right Arrow or `h` and `l`.
- Relative Desk Navigation with Up and Down Arrow or `k` and `j`.
- Movement through the Focused Board's live Sheet Stack with `[` and `]`, including Shift plus `]` to jump to its latest Sheet; Shift plus `[` loads its persisted First Sheet when present.

Organization:

- Moving the Focused Board left or right.
- Moving the Focused Board to the previous or next Desk.
- Board Removal, Board Restoration, and deletion of an eligible empty Desk.
- Overview Selection movement, Overview filtering, and moving the selected Board while Overview remains open.

Adjustment:

- Changing one Board Width or all Board Widths in the Focused Desk.
- Resizing all Boards to fit a chosen count.
- Maximizing or centering the Focused Board.
- Toggling Zen View.

Board Removal and Board Restoration remain repeatable, but their key bindings do not repeat while held. Restoration remains limited to the Recently Removed Board, and Desk deletion remains limited to an eligible empty Desk.

## Return to Sheet Input

Direct work-target confirmation:

- Selecting a Desk by number or with the Desk switcher, including the already Focused Desk.
- Clicking a Board header or Current Sheet to select that Board, including the already Focused Board.
- Entering the Overview Selection, including when it is already the Focused Board in the Focused Desk.
- Moving the Focused Board to a numbered Desk with Shift plus a digit, when the Board actually moves.
- Creating a Board or Desk, including a Desk created from a Built-in or Personal Desk Preset.
- Duplicating the Focused Board's Current Sheet.

Work-content confirmation:

- Confirming an edited Current Sheet URL.
- Confirming a Board Label or Desk Label.

Completion of an independent task:

- Successfully saving or replacing a Personal Desk Preset.
- Finishing Personal Desk Preset management with Done. Deleting Presets within the management presentation keeps that presentation open for further management.

Entering web fullscreen also clears Den Mode because Den commands are unavailable while fullscreen owns the presentation.

## Pointer behavior

The Current Sheet click that returns to Sheet Input also reaches the web content; it is not a separate activation click. Pointer-based organization and adjustment, including Board dragging, resizing, and Removal, keep Den Mode active.

## Temporary-context exclusivity

Every temporary context is exclusive. It accepts only its own operations, cancellation, and application- or window-level operations such as `Command` + `Q` and Shift + `Command` + `W`. Commands that mutate the Den behind it, including `Command` + `T`, `Command` + `L`, and `Command` + `W`, are suspended. Temporary contexts also prevent pointer interaction with the Den behind them.

## Consequences

Den Mode supports sequences of spatial operations without becoming a keyboard prefix. The same state change may produce different transitions according to intent: relative Desk Navigation keeps Den Mode active, while direct Desk selection returns to Sheet Input. Tests must cover user-facing command paths rather than infer transitions solely from state changes.
