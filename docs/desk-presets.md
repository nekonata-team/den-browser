# Desk Presets

Desk Presets provide reusable starting arrangements for repeated work and bookmark-like groups of Sheets. Built-in Desk Presets demonstrate the concept; each Profile owns and persists its Personal Desk Presets independently.

## Captured state

Saving the Focused Desk as a Personal Desk Preset captures:

- Board order, Labels, and Widths
- Current Sheet URLs, including path, query, and fragment
- First Sheet URLs, initialized from each Board's Current Sheet URL
- Terminal Working Directories, optional Zellij session names, zmx session names, and known zmx root session names
- Focused Board index
- Inspection Boards, including their position, width, and Board Group connection to a Target Board

An Inspection Board's Target Board is stored by its position in the Preset.
Applying the Preset creates new Board IDs and reconnects the Inspection Board to the new Target Board ID.
Focus retains its relative position, even when the Focused Board is an Inspection Board.

At least one Board is required.
A Board without a Current Sheet URL remains valid because its Label, Width, position, or terminal content still carries meaning.
Inspection runtime data (such as DOM selections, highlights, and Console events) and live WebKit state (Sheet Stacks, scroll positions, input, and cookies) are not captured.

Creating a Desk from a Desk Preset instantiates fresh Desk and Board identities.
Web Boards receive the Preset's initial Sheet URL as both their Current and First Sheet URL.
Inspection Boards start empty and reconnect to the new Target Board.
Terminal, Zellij, and zmx Boards restore their persisted terminal content.
Replacing a Desk preserves its Desk identity and position while creating new Board identities.
Neither operation keeps the Desk linked to the Preset, while Profile-owned WebKit data preserves site logins.

When a zmx Board's root session name is known, the Personal Desk Preset retains it.
If the session must be recreated, the Board uses this name to restore the `den.root` group label.

## Saving

An outline bookmark button appears left of the Profile control to save the Focused Desk as a Preset.
The same action triggers via `Save Desk as Preset…` in the Den menu or `p` in Den Mode.
Zen View hides the button.
A Desk with no Boards cannot be saved: the button and the menu item are disabled, and `p` is a no-op.

All three actions open a top-center Liquid Glass panel to edit the Desk Preset Label, initialized from the Desk Label.
Saving a new label inserts the preset at the top of My Presets.
Saving an existing label asks before replacing its captured state while preserving its identity and position.
Labels are trimmed, cannot be empty, compare case- and width-insensitively, and cannot collide with reserved built-in labels.

## Creating a Desk

The New Desk panel starts with keyboard focus in Desk Preset search, with Empty as the initial candidate.
Up and Down move the active candidate.
Return or Tab confirms it, initializes the Desk Label, selects it for editing, and advances focus.
Return from the label field creates the Desk.
Escape returns to Preset selection or closes the panel.
During active IME conversion, Return, Tab, and arrow keys pass to the input method instead of panel navigation.
Editing the Desk Label does not modify the underlying Desk Preset.

Empty search keeps Built-in Presets and My Presets grouped.
Typed search ranks fuzzy subsequence matches across both groups: Preset Labels first, followed by Board Labels, then URL hosts or session names.
During Desk creation, a `Create "..."` Empty Desk option is always appended for non-empty search queries.
Confirming this option creates the Desk directly; repeated Return events while the panel closes do not create additional Desks.
The active candidate drives a preview showing Board Labels, URL hosts, session names, and relative widths without capturing Sheet images.

The built-in order is:
1. Empty
2. ChatGPT (three 520-point Boards focused on the first Board)
3. Gemini (three 520-point Boards focused on the first Board)

## Duplicating a Desk

`Duplicate Desk` in a Desk button's context menu immediately creates a Desk with the same Label after the source Desk and switches to it.
Empty Desks can also be duplicated; duplication is disabled at the ten-Desk limit.
The copy uses the same captured Board configuration as a Desk Preset, including the relative Focused Board position, without saving a Personal Desk Preset.
Tutorial Boards are excluded because a Den has at most one Tutorial Board.
Available in-memory Board Facings are copied as initial previews.
Ordinary Terminal Boards start a new Shell in the same Working Directory; Zellij and zmx Boards retain their session names and use the existing session connection behavior.
The source Desk and its live Sheets remain unchanged.

## Replacing a Desk

`Replace Desk…` is available from each Desk button's context menu, or Shift + `p` for the Focused Desk in Den Mode.
Empty is not offered because replacement requires installing at least one Board.
Confirming a Preset initializes an editable Desk Label from its Preset Label.

Replacement preserves Desk identity and position in the Den.
It releases all existing Board runtimes and instantiates independent Boards from the selected Preset.
It applies Preset order, widths, Sheet URLs, and focus, while clearing temporary Board maximization.
Drawer contents, restoration history, and Recently Removed Boards remain untouched.

An empty Desk replaces immediately.
A Desk containing Boards asks for confirmation, warning that live Sheet state will be removed.
Successful replacement enters Sheet Input.

## Managing Personal Desk Presets

Manage Presets opens from `Control` + `P` in Den Mode, the picker's sliders button, or a Desk button's context menu.
In New Desk and Replace Desk, closing management returns to the previous search and selection.
Up and Down navigate through filtered Presets; Return starts renaming the active row.
Pencil and trash buttons rename and delete individual Presets.
Escape cancels an active rename, then returns to the picker or closes standalone management.
Renaming trims the label and rejects empty, duplicate, or Built-in labels without altering captured Boards.

Deleting always asks for confirmation and notes that existing Desks are unaffected.
Deleting the selected Preset resets selection to Empty during creation, or to the first available non-empty Preset during replacement.
Personal Desk Presets have no artificial count limit and are deleted alongside their owning Profile.

## Deferred

- Editing individual Board details inside a Desk Preset
- Import and export
- Sharing between Profiles
- Cloud sync
- Folders, tags, and favorites
- Site-specific built-in width tuning
