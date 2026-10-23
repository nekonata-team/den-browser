---
status: accepted
---

# Use Den Mode for sheet-independent keyboard control

Den Browser uses persistent Den Mode instead of the shared shortcut prefix from [ADR 0003](./0003-keyboard-first-den-operations.md), so users can perform sequences of workspace operations independently of Sheet Input.
The default toggle, `Control` + `,`, avoids Option-based text composition and frequent terminal shortcuts; comma was preferred to period for typing ergonomics and fewer Office web conflicts.
[ADR 0026](./0026-return-to-sheet-input-after-completing-den-mode-actions.md) defines the return-to-input principle; current bindings and transitions are documented in [Shortcuts](../shortcuts.md) and [Keyboard Input](../keyboard-input.md#mode-transitions).
