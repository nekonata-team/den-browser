# Den Browser design

## Intent

Den controls feel like a calm desk laid over live web sheets. Web content remains readable and visually independent; app chrome provides orientation, focus, and lightweight controls.

## Visual rules

- Use dark, low-contrast Den background with restrained Profile-colored ambient light.
- Use Liquid Glass for Den controls, panels, and desk switcher. Do not apply glass treatment to sheet content.
- Boards stay white with rounded continuous corners. Focus uses the active Profile color.
- Use only continuous 8pt, 12pt, and 18pt corner radii: small controls use 8pt, inner cards and inputs use 12pt, and Boards, panels, and Overview use 18pt.
- Keep hierarchy visible: Desk switcher above board strip, board header above sheet, sheet stack indicator secondary.
- Show the current Profile name in the titlebar and a simple Profile icon at the top right. Place the Desk Preset bookmark action immediately to its left when the Focused Desk has Boards. Present both as compact borderless controls with matching secondary tint. Give both icons accessibility labels and help text; Profile identity must not depend on color.
- Prefer SF Symbols and system typography. Preserve macOS accessibility defaults where possible.
- Use SwiftUI semantic text styles such as `title`, `headline`, `body`, `caption`, and `caption2` for app-owned
  text. Apply weight, design, and monospaced variants to a semantic style instead of specifying a point size.
- Avoid `.system(size:)` for app-owned text. Fixed sizes remain appropriate for geometry-bound symbols and
  controls, or when a documented visual requirement cannot be expressed with a semantic text style.
- Keep shared app-owned Den layout metrics in `Features/Den/DenLayout.swift`. Keep component-specific metrics close
  to their component, and introduce a private layout type only when values are reused or participate in a layout
  calculation.
- Share a layout metric only when its uses have the same visual meaning and should change together. Equal numeric
  values alone are not a reason to couple unrelated spacing or dimensions. Local literals are appropriate when a
  name would not add design intent.
- Let SwiftUI semantic colors express standard hierarchy: use `primary`, `secondary`, and `tertiary` for Den text, icons, and neutral chrome.
- Resolve Den chrome in its dark appearance so semantic colors stay legible. Do not hard-code black or white for standard text and icons.
- Reserve fixed colors for semantic meaning such as errors; use the active Profile color for Den atmosphere and focus, plus the dark background gradient and shadows.
- Profile palette colors identify Profiles and tint the active Den context. They may appear on the Focused Board, Overview Selection, Desk switcher, and ambient background.
- In Den Mode, shift the Den background darker and subtly tint the Focused Board header with the active Profile color. Keep Sheets unchanged.

## Interaction rules

- Keyboard operation leads. Pointer actions support it and must keep focused-board state consistent.
- Use the native context menu on Board headers for concise, Board-specific actions. Keep Sheet context menus owned by web content, and focus the targeted Board when its header menu opens.
- Keep context-menu ordering stable by disabling unavailable left/right movement instead of hiding it. Do not show Den Mode-only or configurable key equivalents there.
- Do not make color the only state signal. Focus and direct manipulation need borders, elevation, motion, and accessible labels.
- Keep New Desk keyboard-first: choose an active Desk Preset through fuzzy search and arrow keys, confirm it, then edit the initialized Desk Label before creation. Do not treat search-driven active results as confirmed selections.
- Keep panel copy in product language from `CONTEXT.md`.
- Use brief, bounce-free motion to preserve spatial continuity when Boards move, resize, or change focus.
- Let repeated keyboard input retarget motion immediately instead of waiting for an animation to finish.
- Route app-owned spatial and feedback animations through `DenMotion`. Direct pointer tracking and continuous drag auto-scroll may use interaction-specific motion.
- Motion defaults to following the macOS Reduce Motion setting. Preferences can explicitly select Standard Motion or Reduced Motion for Den.
- Reduced Motion removes spatial animation while preserving brief opacity feedback.

## Zen View

- Zen View hides the native titlebar, Desk switcher, Desk Preset bookmark action, and Profile control together, without hiding controls inside Boards.
- Boards expand into the released upper area, keeping an 8-point inset from the window edge.
- Do not add alternate window dragging, traffic-light controls, or titlebar feedback in Zen View. The darker Den background and tinted Focused Board header continue to show Den Mode.
- Do not reveal hidden controls on pointer hover. Users toggle Zen View with `z` in Den Mode or the Den menu.
- Treat Zen View as window-local runtime presentation. A recreated Den window starts with Zen View off.
- Keep temporary panels, Overview, Empty Den guidance, and the Keyboard Shortcuts guide available while Zen View is active.

## Review checklist

- Is `WKWebView` content readable beneath Den controls?
- Are focus and direct manipulation distinguishable without relying only on color?
- Does keyboard focus still make sense after pointer interaction?
- Does UI use Den, Desk, Board, and Sheet terminology correctly?
- Does Zen View remove native window and Den chrome while preserving Board controls and Den Mode feedback?
