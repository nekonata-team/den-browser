# Inspection

An Inspection Board investigates its target Web Board's Current Sheet. See the [Inspection Board decision](./adr/0056-add-inspection-board-for-joint-web-inspection.md) and [domain terms](../CONTEXT.md).

New Inspection Boards start at 360 points wide. This is an initial size, and their width can be resized independently using the normal Board width limits.

Inspection Boards cannot be duplicated.

Drag the header of either the target Web Board or its Inspection Board to move their Board Group together. Both Boards follow the pointer, and an outline surrounds the group while dragging. The Boards remain independently focusable and resizable.

## Selected element and ancestors

Pick an element in the Current Sheet or select a node in the DOM tree. The DOM tree shows the selected element's ancestor path and lets the user expand and select related nodes.

Page element highlights use the active Profile color for their outline and translucent fill, both when picking and when hovering over a DOM tree node.

Selected Element shows the selected element's own information and related labels. It does not repeat ancestor summaries: ancestors are inspected through the DOM tree, and each container's aggregate text would repeat the text of its descendants.

Element details are captured when an element is selected; select it again to refresh those details. The DOM tree updates while the Inspection Board is visible.

## Reading inspection context with `den`

Agents can create or reuse the Inspection Board linked to a Web Board, then read it by its own Board ID:

```sh
den board inspection new --target <web-board-id> --json
den board inspection read --board <inspection-board-id> --json
```

`den board list --json` identifies an Inspection Board with its `target_board_id`. `den board inspection read` requires that Inspection Board's ID; it does not guess from focus or silently switch to another Board. A successful read is observational: it does not change focus, selection, or the target Sheet.

The JSON response's `inspection` object describes the target page and the inspection data currently available. This includes page metadata, the selected element, accessible labels, a captured CSS selector, when its details were captured, document identity, its ancestor path, retained console and JavaScript events, and the number of dropped events. When there is no selected element, the result reports that state explicitly. Page-dependent details can be absent when the page has not supplied them. Inspection reads leave the optional element `ref` absent because a captured selector can point to a different element after the DOM changes. For current page content and `@e…` references, use the target Web Board ID with `den board web snapshot` or `den board web query`.
