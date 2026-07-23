---
status: proposed
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

## Open questions

- Is web material in the Drawer canonically a `Sheet`, a `Drawer Item` containing Sheet data, or another term? `CONTEXT.md` currently defines a Sheet as a web screen held within a Board, so calling Desk-independent material a Sheet would broaden that definition.
- Does opening an external URL both capture it and show a temporary preview, or capture it without changing the visible work?
- What exact fallback selects the receiving Profile when no Profile window is active?
- Does closing a preview keep its material in the Drawer by default?
- When placing web material, is the primary action “create a Board,” “add to the Focused Board,” or a destination chooser?
- Does “keep Current Sheet in Drawer” copy its recallable state, share identity, or detach it from the Board? The initial recommendation is a copy-like capture with independent identity.
- Which metadata survives: URL, title, favicon, capture time, source application, last viewed time, scroll position, or form state?
- How are duplicate captures represented?
- Is ordering manual, recency-based, or both?
- What retention and bulk-discard controls become necessary as the Drawer grows?
- Where does the cross-Desk preview appear, and does it remain visible while the Focused Desk changes?

## Candidate `CONTEXT.md` language

This glossary text is a draft, not adopted terminology. Move it into `CONTEXT.md` only after the open naming and lifecycle questions are resolved.

```md
**Drawer**:
A Den-wide place for material whose Desk or Board context is not yet settled. It remains available across Desk changes without becoming part of a Desk layout.
_Avoid_: Inbox, Temporary Desk, scratch workspace, clipboard

**Drawer Item**:
Material held in the Drawer before it is placed into an established work context or discarded. A Drawer Item is not implicitly unread, actionable, or temporary in storage.
_Avoid_: Inbox item, task, bookmark, history entry

**Drawer Preview**:
A temporary presentation of a Drawer Item for recall or comparison that does not place the item into a Desk or Board.
_Avoid_: Board, floating Board, temporary Desk

**Drawer Placement**:
Incorporating a Drawer Item into an established Desk or Board context. Placement may create a Board or add material to an existing Board, according to the material type and chosen destination.
_Avoid_: Restore, open tab, move to workspace

**Drawer Discard**:
Releasing material from the Drawer without placing it into a Desk or Board context.
_Avoid_: Complete, archive, close tab
```
