# Desk Presets

Desk Presets provide reusable starting arrangements for repeated work and bookmark-like groups of Sheets. Built-in Desk Presets demonstrate the concept; each Profile owns and persists its Personal Desk Presets independently.

## Captured state

Saving the Focused Desk as a Personal Desk Preset captures:

- Board order
- Board Labels
- Board Widths
- Current Sheet URLs, including path, query, and fragment
- Focused Board

At least one Board is required. A Board without a Current Sheet URL remains valid because its Label, Width, and position can still carry meaning. Sheet Stacks, live `WKWebView` state, scroll positions, input, and sign-in state are not captured.

Creating a Desk from any Desk Preset creates new Desk and Board identities. The new Desk does not remain linked to the Desk Preset. Profile-owned WebKit data still supplies that Profile's existing site sessions.

## Saving

When the Focused Desk contains a Board, an outline bookmark button appears left of the Profile control. The same action is available as `Save Desk as Preset…` in the Den menu and as `p` in Den Mode. Zen View hides the button with the other top controls.

All three actions open the same top-center Liquid Glass panel. Its only editable value is the Desk Preset Label, initialized from the current Desk Label. Saving a new label inserts the Personal Desk Preset at the top of My Presets. Saving an existing Personal Desk Preset Label asks before replacing its captured state while preserving its identity and position. Built-in labels are reserved.

Labels are trimmed, cannot be empty, and compare case-insensitively. A Desk with no Boards cannot be saved: its button is absent, its Den menu item is disabled, and `p` is a no-op.

## Creating a Desk

The New Desk panel starts with keyboard focus in Desk Preset search and treats Empty as the initial active candidate. Up and Down move the active candidate. Return or Tab confirms it, initializes the Desk Label from its Desk Preset Label, selects that label for editing, and advances focus to the Desk Label. Return from the label creates the Desk. Escape from the label returns to Preset selection; Escape there closes the panel. Changing the Desk Label does not change the confirmed Desk Preset.

Empty search keeps Built-in Presets and My Presets grouped. Typed search ranks fuzzy subsequence matches across both groups, prioritizing Desk Preset Labels, then Board Labels, then Current Sheet URL hosts. A single result becomes active but still requires Return or Tab for confirmation. The active candidate drives the preview without becoming the confirmed Desk Preset. The preview shows Board Labels, URL hosts, and relative Board Widths without capturing Sheet images. The built-in order is:

1. Empty
2. ChatGPT
3. Gemini

ChatGPT and Gemini each create three 520-point Boards focused on the first Board. Site-specific built-in widths may be tuned later.

## Managing Personal Desk Presets

`Manage Presets…` switches the New Desk panel to an inline management view. Shift + `p` in Den Mode opens the same management view directly. It supports search and deletion. Built-in Desk Presets are visible during selection but are not managed.

Deleting always asks for confirmation and states that existing Desks are unaffected. Deleting the selected Personal Desk Preset returns selection to Empty.

Personal Desk Presets have no artificial count limit. They are deleted with their owning Profile. Profile documents without the optional list load with no Personal Desk Presets.

## Deferred

- Dedicated Desk Preset editing
- Renaming without capture
- Import and export
- Sharing between Profiles
- Cloud sync
- Folders, tags, and favorites
- Site-specific built-in width tuning
