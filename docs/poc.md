# PoC Criteria

Den Browser's first PoC validates whether a macOS WKWebView implementation can support the Den interaction model.

## Must pass

- ChatGPT, Gemini, and Claude logins remain available after app restart.
- Six boards can be open at the same time.
- Board navigation works from the keyboard without noticeable delay.
- In-progress text inside each board remains available after moving between boards.
- Back and forward navigation can be treated as a sheet stack.
- App restart restores desks, board order, board labels, board widths, current sheet URLs, and the focused board.

## Performance targets

- Text input stays responsive with six boards open.
- Board navigation feels immediate, targeting roughly 100 ms or less.
- CPU does not stay high after 30 minutes idle with six boards open.
- Memory usage stays within a practical range for daily use. The acceptable range should be set after the first measurement pass.

## Design checks

- Liquid Glass controls remain legible over live WKWebView content.
- Den controls use Liquid Glass as a floating navigation/control layer, not as decoration over sheet content.
- Reduced transparency, increased contrast, and reduced motion settings keep the interface usable.
- Focused board and keyboard focus indicators are clear without relying only on color.

## Fail conditions

- AI chat logins do not persist across app restarts.
- ChatGPT, Gemini, or Claude is not usable in WKWebView.
- Three to six boards make input or board navigation clearly sluggish.
- Den shortcuts cannot work reliably while web content has focus.
- WKWebView constraints create a major hole in the core desk, board, or sheet experience.
- Liquid Glass overlays cannot remain legible or accessible over embedded WKWebView content.
