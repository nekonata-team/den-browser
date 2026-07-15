# Den Browser design

## Intent

Den controls feel like a calm desk laid over live web sheets. Web content remains readable and visually independent; app chrome provides orientation, focus, and lightweight controls.

## Visual rules

- Use dark, low-contrast Den background with restrained cyan and Profile-colored ambient light.
- Use Liquid Glass for Den controls, panels, and desk switcher. Do not apply glass treatment to sheet content.
- Boards stay white with rounded continuous corners. Focus uses cyan; held board uses orange.
- Keep hierarchy visible: Desk switcher above board strip, board header above sheet, sheet stack indicator secondary.
- Show the current Profile name in the titlebar and a simple Profile icon at the top right. Give the icon a name-based accessibility label and help text; Profile identity must not depend on color.
- Prefer SF Symbols and system typography. Preserve macOS accessibility defaults where possible.
- Let SwiftUI semantic colors express standard hierarchy: use `primary`, `secondary`, and `tertiary` for Den text, icons, and neutral chrome.
- Resolve Den chrome in its dark appearance so semantic colors stay legible. Do not hard-code black or white for standard text and icons.
- Reserve fixed colors for Den-specific meaning and atmosphere: cyan for focus, orange for held boards, and the dark background gradient and shadows.
- Profile palette colors identify Profiles only; they never replace cyan focus or orange Held Board state.

## Interaction rules

- Keyboard operation leads. Pointer actions support it and must keep focused-board state consistent.
- Do not make color the only state signal. Focus/hold differences need borders, elevation, and accessible labels.
- Keep panel copy in product language from `CONTEXT.md`.

## Zen View

- Zen View hides the Desk switcher and Profile control together, without hiding controls inside Boards.
- Boards expand into the upper area released by those controls.
- Keep the native titlebar, current Profile name, Den Mode and Held Board title states, and cyan Den Mode ring visible.
- Do not reveal hidden controls on pointer hover. Users toggle Zen View with `z` in Den Mode or the Den menu.
- Treat Zen View as window-local runtime presentation. A recreated Den window starts with Zen View off.
- Keep temporary panels, Overview, Empty Den guidance, and the Keyboard Shortcuts guide available while Zen View is active.

## Review checklist

- Is `WKWebView` content readable beneath Den controls?
- Are focused and held boards distinguishable without relying only on color?
- Does keyboard focus still make sense after pointer interaction?
- Does UI use Den, Desk, Board, and Sheet terminology correctly?
- Does Zen View remove only Desk and Profile controls while preserving Profile and Den Mode orientation?
