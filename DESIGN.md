# Den Browser design

## Intent

Den controls feel like a calm desk laid over live web sheets. Web content remains readable and visually independent; app chrome provides orientation, focus, and lightweight controls.

## Visual rules

- Use dark, low-contrast Den background with restrained Profile-colored ambient light.
- Use Liquid Glass for Den controls, panels, the desk switcher, app-owned Inspection and Tutorial Boards, and unactivated Board placeholders.
  Keep Web Sheets visually independent and do not apply glass to sheet content.
- Boards use rounded continuous corners. Focus uses the active Profile color.
- Terminal Boards keep shared Board chrome and focus treatment. Ghostty owns the Terminal surface appearance, text, cursor, selection, and IME presentation.
- Treat a Primary Board and its Side Board as one adjacent group for dragging, reordering, and centering. Keep focus and width individual to each Board.
  Show each Board's own border and raised shadow while dragging; scale it only when motion is enabled. Do not draw a group-wide outline.
  Center using the group's full width, clamped to the scroll bounds.
- Use only continuous 8pt, 12pt, and 18pt corner radii: small controls use 8pt, inner cards and inputs use 12pt, and Boards, panels, and Overview use 18pt.
- Keep the Desk switcher in its own row at the top of the detail column, aligned with the horizontal Board Strip.
  Use a native split view for the on-demand Board Rail sidebar and the horizontal Board Strip so the switcher and
  Strip move together when the Rail opens. Keep the Rail open when focus changes, let it take width from the Strip
  without changing its height or surface colors, and keep the Board header above Sheet with the Sheet stack indicator
  secondary. Show a small Profile-colored dot on each Board with unread Notifications, and include the exact count in
  the row's accessibility label. When a Board receives focus, mark its unread Notifications as read.
- Show the current Profile name in the titlebar and a distinct background gradient for Private Den while preserving its Profile color in the Den glow and controls. Place Notifications, Save Desk as Preset when the Focused Desk has Boards, and Profile controls in the trailing window toolbar. Use native toolbar button styling, and give icons accessibility labels and help text; Profile identity must not depend on color alone.
- Prefer SF Symbols and system typography. Preserve macOS accessibility defaults where possible.
- Use SwiftUI semantic text styles such as `title`, `headline`, `body`, `caption`, and `caption2` for app-owned
  text. Apply weight, design, and monospaced variants to a semantic style instead of specifying a point size.
- Avoid `.system(size:)` for app-owned text. Fixed sizes remain appropriate for geometry-bound symbols and
  controls, or when a documented visual requirement cannot be expressed with a semantic text style.
- Keep shared Den visual tokens, layout metrics, and motion definitions in `Packages/DenDesign/Sources/DenDesign/`. Keep
  component-specific metrics close to their component, and introduce a private layout type only when values are
  reused or participate in a layout calculation.
- Keep feature-specific layout algorithms with their owning component; for example, Board placement logic stays in
  `Features/Board/Presentation/BoardLayout.swift`.
- Share a layout metric only when its uses have the same visual meaning and should change together. Equal numeric
  values alone are not a reason to couple unrelated spacing or dimensions. Local literals are appropriate when a
  name would not add design intent.
- Let SwiftUI semantic colors express standard hierarchy: use `primary`, `secondary`, and `tertiary` for Den text, icons, and neutral chrome.
- Resolve Den chrome in its dark appearance so semantic colors stay legible. Do not hard-code black or white for standard text and icons.
- Reserve fixed colors for semantic meaning such as errors; use the active Profile color for Den atmosphere and focus, plus the dark background gradient and shadows.
- Profile colors identify Profiles and tint the active Den context. They may be built-in presets or user-selected colors, and may appear on the Focused Board, Overview Selection, Desk switcher, and ambient background.
- In Den Mode, shift the Den background darker and subtly tint the Focused Board header with the active Profile color. Keep Sheets unchanged.

## Interaction rules

### Panels

- Share panel width horizontally; let height follow content.
- Use the active Profile color for selected-item highlights.
- A panel should not display the shortcut used to open it.
- Candidate-list selection wraps between the first and last items in both directions. Reuse shared
  selection-navigation logic. Keep Board and Desk movement or reordering separate with
  action-specific boundaries.

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
- Route app-owned spatial and feedback animations through `DenMotion`. Direct pointer tracking and continuous drag auto-scroll may use interaction-specific motion.
- Motion defaults to following the macOS Reduce Motion setting. Preferences can explicitly select Standard Motion or Reduced Motion for Den.
- Reduced Motion removes spatial animation while preserving brief opacity feedback.

## Input and settings

- Every app-owned SwiftUI `TextField` provides an explicit `prompt:`. The prompt describes an example or expected input format; the label describes the field's meaning and remains the accessibility label.
- `TextEditor` has no `prompt:` API. Use an explicit label and short helper text that communicates the same input guidance.
- Toggles, pickers, and sliders commit changes immediately.
- Text settings use a draft and an explicit Save action. Return may submit the same Save action, but leaving the screen does not silently persist an unfinished draft.
- Place explicit setting actions after their helper text and validation message in a trailing action row. Keep navigation and reset actions visually grouped without treating them as the same semantic action.
- Use the shared settings help and validation treatments for repeated explanatory and error text; keep their content and semantics feature-owned.
- Inline Profile names commit on Return; leaving the screen does not commit an unfinished edit.
- Shortcut recording commits a valid binding immediately and reports invalid or conflicting input inline.
- Search and filter fields are transient and never use the persisted-settings contract.

## Error and feedback presentation

Error and feedback presentation is strictly unified into three channels:

- **Action feedback (Toast)**:
  - Use a Toast (`store.showToast`) when an app-owned operation has no otherwise visible result, or when an action, navigation, or clipboard command fails or is blocked without form context.
  - While a file download is active, show a persistent progress card above Toasts in the bottom-right feedback stack. Remove it when the download ends, then report completion or failure with a Toast.
  - Do not use a Toast when the result is already communicated by visible UI state, such as changed content, focus, navigation, selection, or layout.
  - Keep Toasts concise and non-blocking. Never block the user with a modal dialog for actionable or transient operations.
- **Form and input validation (Inline)**:
  - Use inline validation messages (`DenValidationMessage`) directly within the active panel or settings section for invalid formats, missing fields, or shortcut conflicts.
  - Keep validation inline with the draft so the user can correct the input immediately.
- **Blockers and destructive actions (Dialog / Alert)**:
  - Use modal alerts and confirmation dialogs (`.alert`, `.confirmationDialog` / `DenDialogs`) exclusively for irreversible destructive operations (deleting a Desk, clearing browsing data) or system-level configuration blockers where work cannot continue without user action.

## Zen View

- Zen View hides the native titlebar, Desk switcher, Notification, Desk Preset, and Profile controls together, without hiding controls inside Boards.
- Boards expand into the released upper area, keeping an 8-point inset from the window edge.
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
- Offer the Tutorial Board from the empty Desk's Try Tutorial action and `:tutorial`. Keep at most one per Den and keep its state session-only; see [ADR 0056](docs/adr/0056-provide-an-interactive-tutorial-board.md).

## Review checklist

- Is `WKWebView` content readable beneath Den controls?
- Are focus and direct manipulation distinguishable without relying only on color?
- Does keyboard focus still make sense after pointer interaction?
- Does UI use Den, Desk, Board, and Sheet terminology correctly?
- Does Zen View remove native window and Den chrome while preserving Board controls and Den Mode feedback?
- Does Focus Mode preserve Board spatial orientation, keyboard focus, and focused content input across Board kinds?
