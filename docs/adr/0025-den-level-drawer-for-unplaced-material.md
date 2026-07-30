---
status: accepted
---

# Add a Den-level Drawer for material without a settled work context

Den Browser should provide one Drawer per Den as shared working memory across its Desks. The Drawer holds material that the user does not want to lose but is not ready to place in a Desk or Board. It preserves the existing Desk layout, avoids inventing a temporary Desk, and gives parallel work a place for material that falls between established contexts.

The Drawer belongs to the Den rather than an individual Desk. Because one Profile owns one Den and its isolated web identity, Drawer contents must not cross Profile boundaries. Desk switching leaves the same Drawer available. Desk Presets do not include it.

The Drawer is a place, not a workflow state. Its contents are not implicitly unread, actionable, or overdue, and the product should not pressure the user toward an empty Drawer. This distinguishes it from an Inbox. It is also not conventional browser history, a bookmark collection, a task list, or a general clipboard.

## Initial scope

The first supported material should be web material. The primary initial entry point is opening an `http` or `https` link in Den Browser from another application. This is likely many users' first encounter with the Drawer, not a secondary capture feature.

The intended intake flow is:

1. The user opens a link from another application and macOS routes it to Den Browser.
2. Den Browser resolves the receiving Profile, preferring the active or most recently active Profile according to the final external-link routing policy.
3. The link enters that Profile's Den-level Drawer without selecting or modifying a Desk.
4. Den Browser may show a temporary preview while the captured material remains available from the Drawer.
5. The user later places it into a Board or Desk context, keeps it in the Drawer, or discards it.

This routing avoids guessing which Desk owns an externally received link and prevents incidental links from changing an established Desk layout. The current external-link implementation adds a Board directly to the receiving Profile's Focused Desk. That is an interim behavior: implementing this proposal should replace that direct Board creation with Drawer capture. Profile selection remains a separate application-level routing decision; after a Profile is selected, the Drawer removes the need for Desk selection at intake.

A user can also keep a Board's Current Sheet in the Drawer for later recall or temporary comparison with work in another Desk.

Opening Drawer material may create a temporary live preview, but the Drawer should persist only enough state to recall the material; it must not persist `WKWebView` or other live runtime objects. Placing web material into an established context creates a Board or adds a Sheet to a Board, depending on the chosen destination. Discarding removes it from the Drawer.

The first Current Sheet operation should preserve the source Board rather than silently remove a Sheet from its Sheet Stack. A later explicit “stow” operation may move a Sheet if a clear lifecycle and recovery model emerges.

## Possible expansion

The Drawer may later hold text, images, files, selections, quotations, or groups of material. These types share a lifecycle rather than one data representation:

1. Capture material before its work context is settled.
2. Hold it safely across Desk changes and app restarts.
3. Recall or compare it while working elsewhere.
4. Place it into an established context or discard it.

Future media support must not turn the initial design into a speculative generic content model. Start with web material and extract a broader Drawer Item model only when another material type is implemented. Images in particular require separate decisions about file ownership, storage limits, export, drag and drop, and privacy.

## Initial interaction decisions

- Web material is a `Drawer Item`, separate from `Sheet`.
- `Tab` opens and closes the Drawer in Den Mode. The initial implementation has no pointer entry point.
- Den Mode remains independently toggleable while the Drawer is open. Entering Den Mode returns keyboard focus to Drawer Items without collapsing an expanded Preview; returning to Sheet Input focuses that Preview again.
- Opening a Drawer with an expanded Preview enters Sheet Input and focuses its Sheet. Opening one without an expanded Preview keeps Den Mode, and expanding a Preview from Den Mode enters Sheet Input.
- The Drawer appears from the bottom of the Den without changing Desk layout. It has no edge-hover target, handle, or drag interaction, and keeps an outer inset on both sides.
- Drawer Items form a vertical accordion. One item at a time expands into a live `WKWebView` Drawer Preview.
- Opening an external URL captures, selects, and expands a new Drawer Item.
- Closing the Drawer keeps its expanded Preview identity and live runtime for the next open during the current app run. Collapsing a Preview clears that identity and releases the runtime. Both operations keep the Drawer Item.
- Placement creates a Board to the right of the Focused Board, focuses it, removes the Drawer Item, and closes the Drawer.
- Keeping a Current Sheet in the Drawer copies its URL and label with independent identity without opening the Drawer. The source Board remains unchanged.
- Option-clicking an HTTP or HTTPS link in a Current Sheet captures it as a new Drawer Item without opening the Drawer or changing the Current Sheet, Focused Board, or Desk layout.
- URL, title, and the expanded Drawer Item identity persist. Live WebKit state does not; opening a Drawer after relaunch creates a new runtime from the persisted URL.
- New items appear first. Duplicate URLs remain separate items.
- The expanded Preview remains selected across Desk changes.
- An open Drawer uses most of the Den height and gives its Preview the remaining panel width and height.
- Profile fallback when no Profile window is active remains an application-level routing decision.
