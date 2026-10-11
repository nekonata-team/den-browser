# Inspection

An Inspection Board investigates its target Web Board's Current Sheet. See the [Inspection Board decision](./adr/0056-add-inspection-board-for-joint-web-inspection.md) and [domain terms](../CONTEXT.md).

New Inspection Boards start at 360 points wide and can be resized independently within the normal Board width limits.

Inspection Boards cannot be duplicated.

Drag either Board's header to move the Board Group together, with both Boards following the pointer inside a group outline. Each Board remains independently focusable and resizable.

## Selected element and ancestors

Pick an element in the Current Sheet or select a DOM tree node. The tree shows its ancestor path and lets you expand and select related nodes.

Picking an element or hovering over a DOM tree node highlights it with an outline and translucent fill in the active Profile color.

Selected Element shows the element's own information and related labels. Inspect ancestors through the DOM tree; their aggregate text would repeat descendant text.

Element details are captured when an element is selected; select it again to refresh those details. The DOM tree updates while the Inspection Board is visible.

## Reading inspection context with `den`

Create or reuse a Web Board's Inspection Board, then read it by the Inspection Board ID:

```sh
den board inspection new --target <web-board-id> --json
den board inspection read --board <inspection-board-id> --json
```

`den board list --json` identifies an Inspection Board with its `target_board_id`. `den board inspection read` requires that Inspection Board's ID; it does not guess from focus or silently switch to another Board. A successful read is observational: it does not change focus, selection, or the target Sheet.

The JSON response's `inspection` object includes page metadata, the selected element, accessible labels, its captured CSS selector, capture time, document identity, ancestor path, retained console and JavaScript events, and the dropped-event count. It explicitly reports when no element is selected. Optional details may be absent when unavailable; this does not mean the read failed. The optional element `ref` is omitted because DOM changes can make a captured selector point to another element. For current page content and `@e…` references, use the target Web Board ID with `den board web snapshot` or `den board web query`.
