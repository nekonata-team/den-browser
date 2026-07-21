# Den Browser design

## Intent

Den controls feel like a calm desk laid over live web sheets. Web content remains readable and visually independent; app chrome provides orientation, focus, and lightweight controls.

## Visual rules

- Use dark, low-contrast Den background with restrained cyan and Profile-colored ambient light.
- Use Liquid Glass for Den controls, panels, and desk switcher. Do not apply glass treatment to sheet content.
- Boards stay white with rounded continuous corners. Focus uses cyan.
- Keep hierarchy visible: Desk switcher above board strip, board header above sheet, sheet stack indicator secondary.
- Show the current Profile name in the titlebar and a simple Profile icon at the top right. Place the Desk Preset bookmark action immediately to its left when the Focused Desk has Boards. Present both as compact borderless controls with matching secondary tint. Give both icons accessibility labels and help text; Profile identity must not depend on color.
- Prefer SF Symbols and system typography. Preserve macOS accessibility defaults where possible.
- Let SwiftUI semantic colors express standard hierarchy: use `primary`, `secondary`, and `tertiary` for Den text, icons, and neutral chrome.
- Resolve Den chrome in its dark appearance so semantic colors stay legible. Do not hard-code black or white for standard text and icons.
- Reserve fixed colors for Den-specific meaning and atmosphere: cyan for focus, plus the dark background gradient and shadows.
- Profile palette colors identify Profiles only; they never replace cyan focus.
- In Den Mode, shift the Den background to deep navy and cyan and add a cyan top edge to the Focused Board header. Keep Sheets unchanged and the outer ring secondary.

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
- Boards expand into the released upper area, keeping a 10-point inset from the window edge.
- Do not add alternate window dragging, traffic-light controls, or titlebar feedback in Zen View. The cyan Den Mode ring remains visible.
- Do not reveal hidden controls on pointer hover. Users toggle Zen View with `z` in Den Mode or the Den menu.
- Treat Zen View as window-local runtime presentation. A recreated Den window starts with Zen View off.
- Keep temporary panels, Overview, Empty Den guidance, and the Keyboard Shortcuts guide available while Zen View is active.

## Review checklist

- Is `WKWebView` content readable beneath Den controls?
- Are focus and direct manipulation distinguishable without relying only on color?
- Does keyboard focus still make sense after pointer interaction?
- Does UI use Den, Desk, Board, and Sheet terminology correctly?
- Does Zen View remove native window and Den chrome while preserving Board controls and the cyan Den Mode ring?
