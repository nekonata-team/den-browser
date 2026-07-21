---
status: accepted
---

# Customize sheet-independent Den shortcuts as logical keys

Settings initially customizes the five Den actions available while a Sheet may own keyboard input: Toggle Den Mode, Focus Previous Board, Focus Next Board, Move Focused Board Left, and Move Focused Board Right. These bindings are app-wide because they belong to the user's keyboard environment rather than a Profile, apply immediately to every Profile, and remain active in Sheet Input and Den Mode while staying suspended in Overview and creation panels. Den Mode commands, Overview commands, Vim-style Sheet Navigation, entrenched `Command` shortcuts, Escape, and Desk-number bindings remain fixed.

Each action has one binding represented by a logical character or named special key plus modifiers, rather than a physical key position. A binding must include Control, Option, or Command; modifier-only, unmodified, and Shift-only bindings are rejected. Toggle Den Mode must remain assigned, while the four direct Board actions may be unassigned. Duplicate bindings and collisions with existing app shortcuts are rejected, but operating-system and external global-shortcut conflicts are not detected.

Desk-number navigation is also configurable, but as one modifier combination shared by the ten logical digit keys rather than as ten separate actions. The default is `Command` + `Option` + a digit. Settings records the modifier combination from a representative digit and ignores that digit. It is available in Sheet Input only; Den Mode keeps its fixed digit and Shift plus digit commands. A modifier combination must include Control, Option, or Command; Shift alone is rejected, while Shift combined with a primary modifier is allowed.

`AppPreferences` stores only overrides from the defaults, including explicit unassignment, so Reset removes an override and future defaults can evolve for untouched actions. Invalid or unreadable overrides fall back to defaults without preventing launch. Settings provides per-action Reset, Reset All, inline recording with Escape to cancel, and a full effective shortcut guide. The guide is also available from an Empty Den, `?` in Den Mode, and the Den menu.
