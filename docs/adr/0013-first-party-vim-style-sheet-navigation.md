---
status: accepted
---

# Implement Vim-style Sheet Navigation as a first-party script

Den Browser implements the optional Vim-style Sheet Navigation Feature with one small first-party JavaScript resource injected into Sheets. The Feature is disabled by default. Swift persists its settings and applies them to open and future Sheets without reloads; the script owns only Sheet-local keyboard behavior and hint presentation. Users may register Ignored Sites by hostname; navigation stays dormant on that hostname and its subdomains.

The first PoC using bundled Vimium C through `WKWebExtension` loaded its extension context but did not provide usable navigation. Keeping that Chrome-oriented runtime would add an extension archive, third-party source, permissions, and a browser-state adapter for behavior Den needs only in a narrow form. The Vimium C assets and WebExtension integration are therefore removed.

The first-party implementation covers Vimium-like scrolling, counts, link hints, Sheet Stack and URL navigation, find, and Current Sheet URL copying. `f` and its Space alias activate hinted controls; `F` opens a hinted link as a new Board. `Escape` leaves editable controls or cancels temporary input. The script and native message bridge use a dedicated `WKContentWorld`, and privileged requests are accepted only from the main frame while the Feature is active for that Sheet. Den Mode continues to own Desk and Board operations. Omnibox, bookmarks, Visual mode, arbitrary mappings, iframe traversal, Shadow DOM traversal, and inferred clickability are outside this decision. The supported commands are recorded in `docs/vim.md`.
