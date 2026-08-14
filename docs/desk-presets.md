# Desk Presets

Desk Presets provide reusable starting arrangements for repeated work and bookmark-like groups of Sheets. Built-in Desk Presets demonstrate the concept; each Profile owns and persists its Personal Desk Presets independently.

## Captured state

Saving the Focused Desk as a Personal Desk Preset captures:

- Board order
- Board Labels
- Board Widths
- Current Sheet URLs, including path, query, and fragment
- First Sheet URLs, initialized from each Board's Current Sheet URL at capture time
- Terminal Working Directories, optional Zellij session names, and zmx session names
- Focused Board

At least one Board is required. A Board without a Current Sheet URL remains valid because its Label, Width, position, or terminal content can still carry meaning. Sheet Stacks, live `WKWebView` state, scroll positions, input, and sign-in state are not captured.

Creating a Desk from any Desk Preset creates new Desk and Board identities. Web Boards receive the Preset's initial Sheet URL as both their Current Sheet URL and First Sheet URL; Terminal, Zellij, and zmx Boards receive their persisted terminal content. Replacing a Desk preserves its Desk identity and position while creating new Board identities. Neither operation leaves the Desk linked to the Desk Preset. Profile-owned WebKit data still supplies that Profile's existing site sessions.

## Saving

When the Focused Desk contains a Board, an outline bookmark button appears left of the Profile control. The same action is available as `Save Desk as Preset…` in the Den menu and as `p` in Den Mode. Zen View hides the button with the other top controls.

All three actions open the same top-center Liquid Glass panel. Its only editable value is the Desk Preset Label, initialized from the current Desk Label. Saving a new label inserts the Personal Desk Preset at the top of My Presets. Saving an existing Personal Desk Preset Label asks before replacing its captured state while preserving its identity and position. Built-in labels are reserved.

Labels are trimmed, cannot be empty, and compare case-insensitively. A Desk with no Boards cannot be saved: its button is absent, its Den menu item is disabled, and `p` is a no-op.

## Creating a Desk

The New Desk panel starts with keyboard focus in Desk Preset search and treats Empty as the initial active candidate. Up and Down move the active candidate. Return or Tab confirms it, initializes the Desk Label from its Desk Preset Label, selects that label for editing, and advances focus to the Desk Label. Return from the label creates the Desk. Escape from the label returns to Preset selection; Escape there closes the panel. While IME conversion is active, Return, Tab, Shift-Tab, Up, and Down remain available to the input method instead of triggering these panel actions. Changing the Desk Label does not change the confirmed Desk Preset.

Empty search keeps Built-in Presets and My Presets grouped. Typed search ranks fuzzy subsequence matches across both groups, prioritizing Desk Preset Labels, then Board Labels, then Current Sheet URL hosts or terminal session names. A single result becomes active but still requires Return or Tab for confirmation. The active candidate drives the preview without becoming the confirmed Desk Preset. The preview shows Board Labels, URL hosts, terminal session names, and relative Board Widths without capturing Sheet images. The built-in order is:

1. Empty
2. ChatGPT
3. Gemini

ChatGPT and Gemini each create three 520-point Boards focused on the first Board. Site-specific built-in widths may be tuned later.

## Replacing a Desk

`Replace Desk…` is available from each Desk button's context menu. Shift + `p` opens the same action for the Focused Desk in Den Mode. Empty is not offered because replacement must install at least one Board. Confirming a Preset initializes an editable Desk Label from its Desk Preset Label.

Replacing preserves the Desk identity and its position in the Den. It releases every existing Board runtime, creates independent Boards from the selected Desk Preset, applies the Preset's order, widths, Current Sheet URLs, and focus, and clears temporary Board maximization. Drawer contents and the Recently Removed Board remain unchanged.

An empty Desk is replaced immediately. A Desk containing Boards asks for confirmation and reports that its live Sheet state will be removed. Canceling returns to the configured replacement without changing the Desk. Successful replacement enters Sheet Input.

## Managing Personal Desk Presets

`Manage Presets…` switches the Desk Preset picker to an inline management view. Preset management has no dedicated Den Mode shortcut; it remains available from the picker and each Desk button's context menu. It supports search and deletion. Built-in Desk Presets are visible during selection but are not managed.

Deleting always asks for confirmation and states that existing Desks are unaffected. Deleting the selected Personal Desk Preset returns selection to Empty during creation, or to the first available non-empty Preset during replacement.

Personal Desk Presets have no artificial count limit. They are deleted with their owning Profile. Profile documents without the optional list load with no Personal Desk Presets.

## Deferred

- Dedicated Desk Preset editing
- Renaming without capture
- Import and export
- Sharing between Profiles
- Cloud sync
- Folders, tags, and favorites
- Site-specific built-in width tuning
