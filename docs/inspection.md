# Inspection

An Inspection Board investigates its target Web Board's Current Sheet. See the [Inspection Board decision](./adr/0056-add-inspection-board-for-joint-web-inspection.md) and [domain terms](../CONTEXT.md).

## Selected element and ancestors

Pick an element in the Current Sheet or select a node in the DOM tree. The DOM tree shows the selected element's ancestor path and lets the user expand and select related nodes.

Selected Element shows the selected element's own information and related labels. It does not repeat ancestor summaries: ancestors are inspected through the DOM tree, and each container's aggregate text would repeat the text of its descendants.

Element details are captured when an element is selected; select it again to refresh those details. The DOM tree updates while the Inspection Board is visible.
