# PoC Criteria

Den Browser's first PoC validates whether a macOS WKWebView implementation can support the Den interaction model.

## Must pass

- ChatGPT, Gemini, and Claude logins remain available after app restart.
- Two Profiles can stay signed into different identities on the same site, and both identities survive restart.
- Each Profile restores its own Den, including a Held Board at its former placement, and selecting an already-open Profile does not duplicate its window.
- Six boards can be open at the same time.
- Board navigation works from the keyboard without noticeable delay.
- In-progress text inside each board remains available after moving between boards.
- Back and forward navigation can be treated as a sheet stack.
- App restart restores desks, board order, board labels, board widths, current sheet URLs, and the focused board, then shows that board without a scroll animation.

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
- The titlebar exposes the Profile name, and the top-right Profile icon exposes it through an accessibility label and help text; Profile identity does not depend on color.

## Motion validation

1. Select Follow System and confirm Den motion follows the current macOS Reduce Motion setting.
2. Select Standard Motion and confirm Board movement remains smooth even when macOS Reduce Motion is enabled.
3. Select Reduced Motion and confirm spatial motion stops while brief opacity feedback remains.
4. Relaunch the app and switch Profiles; confirm the selected Motion preference persists and remains shared.

## Profile validation

1. Create a second Profile, open the same site in both Profiles, and sign in as different identities.
2. Quit and relaunch; confirm both sign-ins and each Profile's Desks, Boards, URLs, widths, and focus restore independently.
3. Select the same Profile repeatedly from the chip, Profile menu, and `Control` + `Command` + `P`; confirm only one Den window exists.
4. Change Vim-style Sheet Navigation settings and confirm open Sheets in both Profiles update without reloading.
5. Delete the second Profile; confirm its window closes and its Den and website data disappear while Personal remains.
6. With VoiceOver, confirm the Profile icon announces its name and does not rely on color alone.

## Shortcut and Zen View validation

1. In Settings > Shortcuts, record a new binding for each app-wide action and confirm it applies immediately while the Den window is active.
2. Confirm an unmodified key, an existing menu shortcut, and a binding already assigned to another action are rejected. Confirm Escape cancels recording.
3. Clear each optional Board focus and movement shortcut. Confirm Toggle Den Mode cannot be cleared. Reset one shortcut, then Reset All, and confirm the defaults return.
4. Open the complete shortcut guide from Settings, the Den menu, and `?` in Den Mode. Confirm it shows current custom bindings and that `?` or Escape closes the Den Mode guide.
5. In Den Mode, confirm both `n` and Space open the Board panel.
6. Press `z` in Den Mode. Confirm the Desk switcher and Profile control hide together, the titlebar stays visible, and pressing `z` again restores both. Confirm the choice is window-local and is not restored after relaunch.
7. Press `Command` + `W` from Sheet Input and Den Mode and confirm it closes the Focused Board. Press `Shift` + `Command` + `W` and confirm it closes the Profile window. Confirm `Command` + `W` still closes Settings.

## Desk deletion validation

1. Delete an empty Desk and confirm it disappears immediately.
2. Delete a Desk containing Boards, cancel the confirmation, and confirm the Desk and its Boards remain.
3. Delete it again, confirm the warning, and verify the Desk and its Boards disappear. Confirm the last Desk and the source Desk of a Held Board cannot be deleted.

## Vim-style Sheet navigation experiment

The Vimium C 2.12.2 experiment using `WKWebExtension` did not produce usable keyboard navigation in sheets. Loading the extension context succeeded, but its Chrome-oriented background runtime did not provide working Vimium behavior in Den Browser.

The PoC will instead validate a small first-party implementation of Vim-style Sheet Navigation. It is an optional Feature, disabled by default, and is limited to interaction within the current sheet; Den Mode remains responsible for desks and boards.

In Normal mode, `f` opens hints and `Space` is its body-focus-only alias. Editable controls retain ordinary Space input, and a focused link or button retains ordinary Space activation. `F` opens a hinted link as a new Board. `Escape` cancels active hints. The PoC does not preserve Space-to-scroll while Normal mode is active.

Hints cover visible standard actionable elements: links, buttons, form controls, and elements with `role="button"`. The PoC uses standard selectors and does not infer clickability from arbitrary page script or styling.

Focusing an editable control enters Insert state. Outside IME composition, `Escape` blurs that control and returns to Normal state. During IME composition, `Escape` remains available to the IME; a later `Escape` exits the editable control. When hints are visible, `Escape` only cancels the hints.

Hint labels use the configurable hint alphabet, defaulting to the home-row keys `asdfghjkl`. Labels grow to multiple characters as needed. Completing a unique label performs the element's ordinary activation in the Current Sheet, or opens a link as a new Board after `F`.

Settings exposes the hint alphabet as a string. It defaults to `asdfghjkl`, accepts ASCII letters and digits, lowercases letters, removes duplicates, and requires at least two distinct characters. Invalid input is shown as an error and is not persisted. Settings also accepts Ignored Sites, one hostname or URL per line. URLs are reduced to hostnames, duplicates are removed, and each hostname covers its subdomains.

Each `Space` invocation discovers eligible elements from the current viewport, so dynamic pages are supported without a mutation observer. Hidden and disabled elements are excluded. iframe contents and Shadow DOM are outside this PoC.

Feature enablement and hint-alphabet changes apply immediately to open sheets without reloading them. Disabling the Feature removes active hints and makes its key handling dormant. The same settings apply to future sheets and navigations.

In Normal state, `j` / `k` and `h` / `l` scroll by about 60 points, `d` / `u` scroll by half a viewport, `gg` / `G` move to vertical edges, and `0` / `$` and `zH` / `zL` move to horizontal edges. Numeric prefixes multiply relative movement. `H` / `L`, `r`, `gu` / `gU`, `yy`, and `/` with `n` / `N` provide Sheet Stack, URL, clipboard, and find operations. The target is the scrollable area beneath the viewport center, falling back to the Sheet's main scrolling element. Insert state and key presses with Command, Option, or Control remain available to the Sheet.

The implementation is one small first-party JavaScript resource. The Vimium C archive, third-party source, and `WKWebExtension` integration are removed. Swift is responsible only for persisted settings and applying configuration to live sheets.

Validate the Feature on a general page and in ChatGPT:

1. Enable it in Settings and confirm relative, half-viewport, edge, and counted scrolling commands affect the Sheet or its central scrollable area.
2. Press `f` or `Space`, type a displayed label, and confirm the target receives its ordinary activation. Press `F` and confirm a hinted link opens as a new Board.
3. Focus a text field and confirm Space remains text input; press `Escape` and confirm focus leaves the field and hints can then start.
4. During Japanese IME composition, confirm `Escape` remains available to the IME and a later `Escape` leaves the field.
5. Change the hint alphabet and confirm the next invocation uses it without reloading the Sheet.
6. Disable the Feature and confirm active hints disappear and the page receives its keys again.
7. Add the current hostname to Ignored Sites and confirm the page receives its keys without reloading; remove it and confirm navigation resumes.
8. Confirm `H` / `L`, `r`, `gu` / `gU`, `yy`, `/`, and `n` / `N` perform their documented actions.

## Fail conditions

- AI chat logins do not persist across app restarts.
- ChatGPT, Gemini, or Claude is not usable in WKWebView.
- Three to six boards make input or board navigation clearly sluggish.
- Den shortcuts cannot work reliably while web content has focus.
- WKWebView constraints create a major hole in the core desk, board, or sheet experience.
- Liquid Glass overlays cannot remain legible or accessible over embedded WKWebView content.
