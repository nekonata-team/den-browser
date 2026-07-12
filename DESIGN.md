# Den Browser design

## Intent

Den controls feel like a calm desk laid over live web sheets. Web content remains readable and visually independent; app chrome provides orientation, focus, and lightweight controls.

## Visual rules

- Use dark, low-contrast Den background with restrained cyan and orange ambient light.
- Use Liquid Glass for Den controls, panels, and desk switcher. Do not apply glass treatment to sheet content.
- Boards stay white with rounded continuous corners. Focus uses cyan; held board uses orange.
- Keep hierarchy visible: Desk switcher above board strip, board header above sheet, sheet stack indicator secondary.
- Prefer SF Symbols and system typography. Preserve macOS accessibility defaults where possible.

## Interaction rules

- Keyboard operation leads. Pointer actions support it and must keep focused-board state consistent.
- Do not make color the only state signal. Focus/hold differences need borders, elevation, and accessible labels.
- Keep panel copy in product language from `CONTEXT.md`.

## Review checklist

- Is `WKWebView` content readable beneath Den controls?
- Are focused and held boards distinguishable without relying only on color?
- Does keyboard focus still make sense after pointer interaction?
- Does UI use Den, Desk, Board, and Sheet terminology correctly?
