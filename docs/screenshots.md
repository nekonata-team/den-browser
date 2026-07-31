# Screenshots

Den Browser captures screenshots at two scopes in Den Mode:

- `s` captures the visible web content in the Focused Board's Current Sheet.
- Shift + `s` captures the Focused Desk as one horizontal image. It includes every Board's visible Current Sheet in Board order, labels each Board, and preserves their relative widths.

Both actions open the macOS save panel and write a PNG only after the user chooses a destination. The same actions are available from the Den menu and the relevant Board or Desk context menu.

Current Sheet capture intentionally means the visible Sheet viewport, not the full scrollable document. Desk capture combines those visible viewports rather than scrolling or changing any Current Sheet. A Desk image is scaled down proportionally when its natural width would exceed 16,384 points.
