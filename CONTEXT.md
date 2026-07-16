# Den Browser

## Language

Den Browser is a browser that manages web work as personal work areas instead of tab-list entries.

**Profile**:
An isolated web identity that has one Den and keeps its sign-ins and site data separate from other profiles.
_Avoid_: Account, login

**Den**:
The full personal work environment for one Profile that contains all desks.
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

**Sheet Input**:
The keyboard context in which the Current Sheet receives input instead of Den. Sheet Input may provide ordinary web input or Vim-style Sheet Navigation.
_Avoid_: Normal mode, browser mode

**Vim-style Sheet Navigation**:
An optional keyboard interaction style for navigating within the current sheet. It is distinct from Den Mode and board navigation.
_Avoid_: Vimium C mode, extension mode, Den Mode

**Ignored Site**:
A hostname on which Vim-style Sheet Navigation remains dormant. Ignoring a hostname also ignores its subdomains.
_Avoid_: Blocked site, disabled Sheet

**Den Mode**:
An explicit keyboard context in which Den receives navigation and board-management input instead of the Current Sheet. It persists until the user returns to Sheet Input.
_Avoid_: Command mode, navigation mode

**Zen View**:
A temporary Den presentation that hides Desk and Profile controls so Boards receive more display area. It does not change keyboard ownership or Sheet behavior.
_Avoid_: Zen Mode, Compact Mode

**Den Mode Toggle**:
The action that switches keyboard ownership between Sheet Input and Den Mode.
_Avoid_: Leader, prefix, mode key

**Board Removal**:
Taking a board off its desk and ending its live sheet runtime.
_Avoid_: Close tab, delete page, trash

**Recently Removed Board**:
The most recent board removed from one Profile's Den during the current app run and still available for restoration.
_Avoid_: Closed tab, trash, Held Board, undo history

**Board Restoration**:
Returning the Recently Removed Board to a desk with its saved board identity, label, width, and Current Sheet URL.
_Avoid_: Undo, reopen tab, restore Sheet Stack
