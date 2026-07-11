# Testing

Den Browser splits verification between deterministic unit tests and a human PoC harness. UI tests remain limited to stable, local behavior; they do not automate external websites or login flows.

## Responsibilities

Automated unit tests own:

- `DenStore` and other pure state transitions, including board focus, ordering, moving, holding, placing, canceling, and closing.
- State persistence and restoration.
- The pointer-focus state machine used to coordinate board selection and WebKit focus.

The human harness owns behavior that depends on macOS, WebKit, remote services, or visual judgment:

- Real interaction with `WKWebView`, including navigation and text entry.
- First-responder handoff between Den controls and web content.
- Login persistence for ChatGPT, Gemini, and Claude across app restarts.
- Responsiveness, CPU, and memory with six live boards.
- Liquid Glass legibility and accessibility with Reduced Transparency, Increase Contrast, and Reduce Motion.

## Automated commands

Run from the repository root. Both commands use the shared `Den Browser` scheme, the local macOS destination, a repository-local DerivedData directory, and disabled code signing.

```sh
xcodebuild build \
  -project "Den Browser/Den Browser.xcodeproj" \
  -scheme "Den Browser" \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project "Den Browser/Den Browser.xcodeproj" \
  -scheme "Den Browser" \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data \
  -only-testing:'Den BrowserTests' \
  CODE_SIGNING_ALLOWED=NO
```

Before merge, use this order: build and unit tests, code review, human harness, then merge.

## PoC human smoke checklist

- [ ] Launch Den Browser. Press `Control` + `Option` + `N`; create an Empty desk and a `ChatGPT ×3` desk.
- [ ] Press `Control` + `Option` + Space; open enough boards to keep six live at once. Confirm a new board appears right of the focused board.
- [ ] Use `Control` + `Option` + Left/Right to cycle board focus and Up/Down to cycle desk focus. Confirm movement feels immediate and wraps at each end.
- [ ] Click a board's header and web content. Confirm board focus follows the click and typing goes to the clicked `WKWebView` without an extra click.
- [ ] Enter unfinished text in multiple boards, move between them, and confirm text remains.
- [ ] Navigate within a board. Use `Control` + `Option` + `[`/`]` and confirm back/forward sheet navigation.
- [ ] Use `Control` + `Option` + Shift + Left/Right to reorder a board; use Shift + Up/Down with the same prefix to move it between desks. Confirm focus and placement remain clear.
- [ ] Press `Control` + `Option` + `H`, choose a target with board/desk focus shortcuts, then press `Control` + `Option` + `P`. Repeat and press Escape to confirm cancel leaves the board in place.
- [ ] Use `Control` + `Option` + `-`/`;` to resize, `Control` + `Option` + Return to duplicate, and `Control` + `Option` + `W` to close. Confirm all use the focused board.
- [ ] Press `Control` + `Option` + `O`. Move selection with arrows, reorder with Shift + arrows, enter with Return, and dismiss with Escape.
- [ ] Sign in to ChatGPT, Gemini, and Claude manually. Quit and relaunch; confirm login state remains.
- [ ] Quit and relaunch. Confirm desk order, board order, labels, widths, current URLs, and focused desk/boards restore.
- [ ] With six boards, type and switch boards; observe responsiveness. Leave idle for 30 minutes and inspect CPU and memory in Activity Monitor.
- [ ] Check Liquid Glass controls over varied web content. Repeat with Reduced Transparency, Increase Contrast, and Reduce Motion enabled; confirm controls and focus indicators remain usable and do not rely only on color.
