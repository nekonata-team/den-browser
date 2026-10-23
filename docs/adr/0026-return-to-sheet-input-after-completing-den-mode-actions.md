---
status: accepted
---

# Return to Sheet Input after completing Den Mode actions

Den Mode keeps repeatable exploration, organization, and adjustment active, while successful target confirmation or task completion returns to Sheet Input; cancellation restores the originating context, and invalid or failed operations preserve it.
This refines [ADR 0009](./0009-den-mode-for-sheet-independent-keyboard-control.md) according to user intent rather than state changes alone: relative Desk navigation continues exploration, while direct selection confirms a destination, even when already focused.
The operation categories and pointer behavior are specified in [Keyboard Input](../keyboard-input.md#mode-transitions); tests must exercise user-facing command paths rather than infer transitions solely from mutations.
