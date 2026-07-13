# Den Browser

## Language

Den Browser is a browser that manages web work as personal work areas instead of tab-list entries.

**Den**:
The full personal work environment that contains all desks.
_Avoid_: Workspace, studio, office, space

**Desk**:
A broad work context that holds boards in a horizontal work area. A desk may exist before any boards are added.
_Avoid_: Workspace, window, tab bar, deck

**Desk Label**:
A user-visible label for a desk's broad work context.
_Avoid_: Workspace name, window title

**Desk Template**:
A reusable starting arrangement applied when creating a desk, including its initial boards and their layout. Once created, the desk is independent of the desk template.
_Avoid_: Workspace template, preset, saved desk

**Board**:
A user-created work surface that holds one focused task context and its sheet stack within a desk.
_Avoid_: Tab, card, pane, slot

**Board Label**:
A user-visible label for a board's task context. A board label may be inferred from a sheet or set by the user.
_Avoid_: Tab title, page title, board name

**Board Width**:
The horizontal size of a board within a desk. A board width can be adjusted to fit the work.
_Avoid_: Window size, pane size

**Sheet**:
A web screen held within a board. A sheet is the content being viewed, not the work surface itself.
_Avoid_: Page, view, document

**Sheet Stack**:
The back-forward sequence of sheets within one board.
_Avoid_: Browser history, tab stack, card stack

**Current Sheet**:
The sheet currently shown from a board's sheet stack.
_Avoid_: Active page, top page, visible sheet

**Focused Board**:
The board currently selected for work within a desk.
_Avoid_: Active tab, current page

**Overview Selection**:
A temporary board selection inside overview. The overview selection becomes the focused board only when the user enters it.
_Avoid_: Focused board, active board

**Board Navigation**:
Moving focus between boards in a desk. Board navigation is distinct from scrolling within a sheet.
_Avoid_: Desk scrolling, tab switching

**Vim-style Sheet Navigation**:
An optional keyboard interaction style for navigating within the current sheet. It is distinct from Den Mode and board navigation.
_Avoid_: Vimium C mode, extension mode, Den Mode

**Ignored Site**:
A hostname on which Vim-style Sheet Navigation remains dormant. Ignoring a hostname also ignores its subdomains.
_Avoid_: Blocked site, disabled Sheet

**Den Mode**:
An explicit keyboard context in which Den receives navigation and board-management input instead of the current sheet. It persists until the user exits it.
_Avoid_: Command mode, navigation mode

**Cut Board**:
A board temporarily removed from its desk for placement elsewhere or restoration to its former placement. Only one cut board may exist at a time.
_Avoid_: Dragged tab, selected board, clipboard item

**Board Placement**:
Placing a cut board into a desk.
_Avoid_: Tab move, window move, paste
