# Inspection

An Inspection Board investigates its target Web Board's Current Sheet. See the [Inspection Board decision](./adr/0056-add-inspection-board-for-joint-web-inspection.md) and [domain terms](../CONTEXT.md).

New Inspection Boards start at 360 points wide. This is an initial size, and their width can be resized independently using the normal Board width limits.

Inspection Boards cannot be duplicated.

## Selected element and ancestors

Pick an element in the Current Sheet or select a node in the DOM tree. The DOM tree shows the selected element's ancestor path and lets the user expand and select related nodes.

Page element highlights use the active Profile color for their outline and translucent fill, both when picking and when hovering over a DOM tree node.

Selected Element shows the selected element's own information and related labels. It does not repeat ancestor summaries: ancestors are inspected through the DOM tree, and each container's aggregate text would repeat the text of its descendants.

Element details are captured when an element is selected; select it again to refresh those details. The DOM tree updates while the Inspection Board is visible.

## Reading inspection context with `den`

Agents can create or reuse the Inspection Board linked to a Web Board, then read it by its own Board ID:

```sh
den board inspection new --target <web-board-id> --json
den inspection read --board <inspection-board-id> --json
```

`den board list --json` identifies an Inspection Board with its `target_board_id`. `den inspection read` requires that Inspection Board's ID; it does not guess from focus or silently switch to another Board. A successful read is observational: it does not change focus, selection, or the target Sheet.

The JSON response's `inspection` object describes the target page and the inspection data currently available. This includes page metadata, the selected element, accessible labels, a CSS selector and optional `@e…` reference, when its details were captured, document identity, its ancestor path, retained console and JavaScript events, and the number of dropped events. When there is no selected element, the result reports that state explicitly. Page-dependent details can be absent when the page has not supplied them. For current page content beyond the selected element, use the target Web Board ID with `den sheet` commands.
