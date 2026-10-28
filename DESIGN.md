# Den Browser design

## Intent

Den controls feel like a calm desk laid over live web sheets. Web content remains readable and visually independent; app chrome provides orientation, focus, and lightweight controls.

Implementation contracts live beside their definitions: [layout metrics](Packages/DenViews/Sources/DenViews/Shared/LayoutMetrics.swift),
[panel controls](Packages/DenViews/Sources/DenViews/Shared/DenPanel.swift),
[colors](Packages/DenViews/Sources/DenViews/Shared/DenColors.swift), and
[motion and corner radii](Packages/DenViews/Sources/DenViews/Shared/DenMotion.swift).
Package responsibilities are defined in [Architecture](docs/architecture.md).

## Visual rules

- Use dark, low-contrast Den background with restrained Profile-colored ambient light.
- Use Liquid Glass for Den controls, panels, the desk switcher, app-owned Inspection and Tutorial Boards, and unactivated Board placeholders.
  Keep Web Sheets visually independent and do not apply glass to sheet content.
- Prefer system controls and button styles; avoid unnecessary custom glass layering.
- Panels retain system control styling and keyboard focus behavior while suppressing automatic focus rings.
- Boards use rounded continuous corners. Focus uses the active Profile color.
- Terminal Boards keep shared Board chrome and focus treatment. Ghostty owns the Terminal surface appearance, text, cursor, selection, and IME presentation.
- Treat a Primary Board and its Side Board as one adjacent group for dragging, reordering, and centering. Keep focus and width individual to each Board.
  Show each Board's own border and raised shadow while dragging; scale it only when motion is enabled. Do not draw a group-wide outline.
- Use a consistent hierarchy of continuous corners for controls, inner surfaces, and outer surfaces.
- Keep the Desk switcher in its own row at the top of the detail column, aligned with the horizontal Board Strip.
  Align the Desk list and New Desk button together within the detail column when they fit, using the Appearance setting
  (Left by default, or Center); otherwise allow horizontal scrolling.
  Keep the switcher and Strip aligned as the on-demand Board Rail opens. Keep the Rail open when focus changes, let it take width from the Strip
  without changing its height or surface colors, and keep the Board header above Sheet with the Sheet stack indicator
  secondary. Use the Profile color for the selected Rail row's background while the Rail does not own keyboard focus.
  While the Rail owns focus, remove that background and use native selection styling to avoid blending the two colors.
  Show a small Profile-colored dot on each Board with unread Notifications, and include the exact count in
  the row's accessibility label. When a Board receives focus, mark its unread Notifications as read.
- Show the current Profile name in the titlebar and a distinct background gradient for Private Den while preserving its Profile color in the Den glow and controls. Place Notifications, Save Desk as Preset when the Focused Desk has Boards, and Profile controls in the trailing window toolbar. Use native toolbar button styling, and give icons accessibility labels and help text; Profile identity must not depend on color alone.
- Put the native Universal Search toolbar button before Notifications, Save Desk as Preset, and Profile controls.
- Present Notifications in a native popover anchored to the toolbar bell. In Zen View, where the toolbar is hidden, retain the upper-right notification panel. Preserve keyboard selection, Escape dismissal, and return of input to the focused Board when the popover closes.
  Keep Universal Search visually separate from the other controls while retaining native toolbar appearance.
  Show a secondary `⌘P` hint after its Search label.
  All entrances open the same palette; use `>` to restrict results to commands. Keep candidate actions explicit:
  switching to an existing Board and creating a Board from an Essential or Recent Item are distinct results.
  With empty input, show Recent (at most five), Essentials, Boards, Desks, Profiles, then commands.
  Boards include all Desks in the current Profile, preserving Desk and Board order.
  With input, search all Recent Items and show at most five matches alongside the other candidate types.
  Recent results use a leading clock symbol and the trailing creation symbol.
  Give candidates leading SF Symbols for their target or command; use the existing Board-kind symbols for Boards.
  Show a trailing arrow for switching, `plus.app` for creation, and chevron for command execution.
  Hide the toolbar entrance in Overview and Zen View; keyboard entrances remain available in Zen View.
- Prefer SF Symbols and system typography. Preserve macOS accessibility defaults where possible.
- Use `.xmark` to dismiss UI or close an active work surface, including removing a Board from its Desk.
  Use `.trash` to discard a collection item, such as a Drawer or Recent Item; restoration availability does not change the symbol.
- Use SwiftUI semantic text styles such as `title`, `headline`, `body`, `caption`, and `caption2` for app-owned
  text. Apply weight, design, and monospaced variants to a semantic style instead of specifying a point size.
- Avoid `.system(size:)` for app-owned text. Fixed sizes remain appropriate for geometry-bound symbols and
  controls, or when a documented visual requirement cannot be expressed with a semantic text style.
- Share visual values only when they have the same design meaning and should change together.
  Keep component-specific layout decisions with their owner.
- Let SwiftUI semantic colors express standard hierarchy: use `primary`, `secondary`, and `tertiary` for Den text, icons, and neutral chrome.
- Keep shared input, Board, and candidate-row treatments consistent across features and interaction states.
  Distinguish selection backgrounds and focus outlines from shadows and ambient effects.
- Resolve Den chrome in its dark appearance so semantic colors stay legible. Do not hard-code black or white for standard text and icons.
- Reserve fixed colors for semantic meaning such as errors; use the active Profile color for Den atmosphere and focus, plus the dark background gradient and shadows.
- Profile colors identify Profiles and tint the active Den context. They may be built-in presets or user-selected colors, and may appear on the Focused Board, Overview Selection, Desk switcher, and ambient background.
- In Den Mode, shift the Den background darker and subtly tint the Focused Board header with the active Profile color. Keep Sheets unchanged.

## Interaction rules

### Panels

- Share panel width horizontally; let height follow content.
- Keep temporary panel inputs at a stable position as content grows or shrinks. Placement and exceptions belong to
  [the panel overlay](Packages/DenViews/Sources/DenViews/Den/DenActivePanelOverlay.swift).
- Use the active Profile color for selected-item highlights.
- A panel should not display the shortcut used to open it.
- Place keyboard navigation and action hints at the bottom of panels.
- Candidate-list selection wraps in both directions; Board and Desk movement or reordering respects
  action-specific boundaries. The reusable contract is documented in
  [selection navigation](Packages/DenModels/Sources/DenModels/Den/SelectionNavigation.swift).

- Keyboard operation leads. Pointer actions support it and must keep focused-board state consistent.
- Use native, Board-specific context menus where a Board kind provides them. Opening a Web Board header menu focuses that Board.
  Keep Sheet context menus owned by web content.
- BoardRail context menus target the clicked Board without changing focus when they open.
- Reserve Sheet-only controls for Web Boards. Terminal Boards add font-size controls; zmx Boards expose zmx Sessions.
- Keep context-menu ordering stable by disabling unavailable left/right movement instead of hiding it. Do not show Den Mode-only or configurable key equivalents there.
- Do not make color the only state signal. Focus and direct manipulation need borders, elevation, motion, and accessible labels.
- Keep New Desk and Replace Desk keyboard-first: choose an active Desk Preset through fuzzy search and arrow keys, confirm it, then edit the initialized Desk Label before applying it. Do not treat search-driven active results as confirmed selections.
- Keep panel copy in product language from `CONTEXT.md`.
- Use brief, bounce-free motion to preserve spatial continuity when Boards move, resize, or change focus.
- Let repeated keyboard input retarget motion immediately instead of waiting for an animation to finish.
- Motion defaults to following the macOS Reduce Motion setting. Preferences can explicitly select Standard Motion or Reduced Motion for Den.
- Reduced Motion removes spatial animation while preserving brief opacity feedback.

## Input and settings

- Every app-owned text input has a meaningful accessibility label and explicit input guidance.
  Single-line fields show an example or expected format as a prompt; multiline editors use short helper text.
- Toggles, pickers, and sliders commit changes immediately.
- Text settings use a draft and an explicit Save action. Return may submit the same Save action, but leaving the screen does not silently persist an unfinished draft.
- Keep setting explanations, validation, and explicit actions in a clear reading order; distinguish save, navigation,
  and reset actions. Presentation contracts live in
  [the settings controls](Packages/DenViews/Sources/DenViews/Settings/SettingsForm.swift).
- Inline Profile names commit on Return; leaving the screen does not commit an unfinished edit.
- Shortcut recording commits a valid binding immediately and reports invalid or conflicting input inline.
- Search and filter fields are transient and never use the persisted-settings contract.

## Error and feedback presentation

Error and feedback presentation is strictly unified into three channels:

- **Action feedback (Toast)**:
  - Use a Toast when an app-owned operation has no otherwise visible result, or when an action, navigation, or clipboard command fails or is blocked without form context.
  - While a file download is active, show a persistent progress card above Toasts in the bottom-right feedback stack. Remove it when the download ends, then report completion or failure with a Toast.
  - Do not use a Toast when the result is already communicated by visible UI state, such as changed content, focus, navigation, selection, or layout.
  - Keep Toasts concise and non-blocking. Never block the user with a modal dialog for actionable or transient operations.
- **Form and input validation (Inline)**:
  - Use inline validation messages directly within the active panel or settings section for invalid formats, missing fields, or shortcut conflicts.
  - Keep validation inline with the draft so the user can correct the input immediately.
- **Blockers and destructive actions (Dialog / Alert)**:
  - Use modal alerts and confirmation dialogs exclusively for irreversible destructive operations (deleting a Desk, clearing browsing data) or system-level configuration blockers where work cannot continue without user action.

## Zen View

- Zen View hides the native titlebar, Desk switcher, Notification, Desk Preset, and Profile controls together, without hiding controls inside Boards.
- Boards expand into the released upper area while preserving the shared window-edge inset.
- Do not add alternate window dragging, traffic-light controls, or titlebar feedback in Zen View. The darker Den background and tinted Focused Board header continue to show Den Mode.
- Do not reveal hidden controls on pointer hover. Users toggle Zen View with `z` in Den Mode or the Den menu.
- Treat Zen View as window-local runtime presentation. A recreated Den window starts with Zen View off.
- Keep temporary panels, Overview, Empty Den guidance, and the Keyboard Shortcuts guide available while Zen View is active.

## Focus Mode

- Focus Mode keeps the Focused Board's content clear and blurs unfocused Web Sheets and Terminal surfaces.
  Inspection and Tutorial Boards use shared focus chrome without a blur.
- Keep non-focused Board Headers, labels, order, widths, and direct manipulation visible so the Desk's spatial map remains usable.
- Keep the existing Focused Board ring as the boundary cue; in Focus Mode, add only a subtle Profile-colored halo to give it quiet foreground presence. Reserve Header tint for Den Mode.
- Treat Focus Mode as window-local runtime presentation. A recreated Den window starts with Focus Mode off, while Den Mode, Sheet Input, and Desk changes do not turn it off.
- Do not pause, mute, or alter web content as part of Focus Mode. The effect is visual only.
- Keep Focus Mode optional and user-controlled; describe it as a visual presentation aid.

## Tutorial Board

- Present Getting Started as an app-owned checklist with Liquid Glass treatment and shared Board focus behavior.
- Keep Tutorial Board header controls for movement, centering, and removal; do not provide a header context menu or duplication.
- Advance checklist steps only after the matching Den operation succeeds, not when the user requests it. Require Web Board creation, keyboard Board navigation, then Desk creation; show optional shortcuts and Terminal steps after the required sequence.
- Offer the Tutorial Board from the empty Desk's Try Tutorial action and `:tutorial`. Keep at most one per Den and keep its state session-only; see [ADR 0063](docs/adr/0063-provide-an-interactive-tutorial-board.md).

## Review checklist

- Is `WKWebView` content readable beneath Den controls?
- Are focus and direct manipulation distinguishable without relying only on color?
- Does keyboard focus still make sense after pointer interaction?
- Does UI use Den, Desk, Board, and Sheet terminology correctly?
- Does Zen View remove native window and Den chrome while preserving Board controls and Den Mode feedback?
- Does Focus Mode preserve Board spatial orientation, keyboard focus, and focused content input across Board kinds?
