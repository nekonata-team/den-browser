# Den Browser

## Language

Den Browser manages long-running web and terminal work as personal work areas instead of tab-list entries or separate terminal windows.

**Profile**:
An isolated web identity that has one Den and keeps its sign-ins and site data separate from other profiles.
_Avoid_: Account, login

**Den**:
The full personal work environment for one Profile that contains all desks.
_Avoid_: Workspace, studio, office, space

**Private Den**:
A temporary Den for a single private browsing session. It is separate from persistent Profile-owned Dens and does not carry its web identity or Den state into a later session. It is private on the device, not an anonymity or network privacy boundary.
_Avoid_: Incognito window, private profile, anonymous browser

**Desk**:
A broad work context that holds boards in a horizontal work area. A desk may exist before any boards are added.
_Avoid_: Workspace, window, tab bar, deck

**Desk Label**:
A user-visible label for a desk's broad work context.
_Avoid_: Workspace name, window title

**Desk Preset**:
A reusable starting arrangement applied when creating a desk or replacing a desk's contents, including its initial boards, current sheets, and layout. A desk remains independent of the desk preset after it is applied.
_Avoid_: Workspace template, Desk Layout, saved desk

**Personal Desk Preset**:
A Profile-owned desk preset captured from an existing desk for repeated work or bookmark-like starting points.
_Avoid_: Saved desk, bookmark folder

**Built-in Desk Preset**:
An app-provided desk preset available to every Profile as an example or common starting point.
_Avoid_: Default desk, system desk

**Desk Preset Label**:
A user-visible label for a desk preset. It becomes the initial Desk Label when the desk preset is selected for creation or replacement.
_Avoid_: Desk Label, preset name

**Board**:
A user-created or app-provided clipboard-like work surface that holds one focused task context within a desk and presents its Sheet content.
_Avoid_: Tab, card, pane, slot

**Tutorial Board**:
An app-provided Board that presents Den-owned tutorials as interactive checklists. A Den has at most one Tutorial Board, opened from an empty Desk or from Open Board with `:tutorial`. When multiple tutorials are available, users can select one from its catalog.
_Avoid_: Demo Desk, tour screen

**Web Board**:
A Board whose content is a back-forward Sheet Stack.
_Avoid_: Browser tab

**Side Board**:
A separately focusable companion Board attached to a target Board. A target has at most one Side Board.

**Board Role**:
A Board's place in a Board Group: Primary Board or Side Board.

**Primary Board**:
The Board that a Side Board attaches to. A standalone Board is the Primary Board of its one-Board group.

**Board Group**:
A target Board and its optional Side Board, considered together as one unit.

**Inspection**:
A focused investigation of a selected element in a Web Board's Current Sheet, using related elements and console output as evidence.
_Avoid_: Debug session

**Inspection Board**:
A Side Board for a human and AI to investigate its target Web Board.
_Avoid_: InspectBoard, Web Inspector

**Terminal Board**:
A Board that presents one Sheet for a live Terminal Session. Its process remains live across Desk changes while the Profile Window remains open.
_Avoid_: Terminal window, terminal tab, pane

**Terminal Session**:
The live shell, Zellij session, or zmx session, terminal screen, and scrollback owned by a Terminal Board. An ordinary Terminal Board persists only its latest reported Working Directory. Named Zellij and zmx Boards persist their session name; a Zellij Board without a name opens Zellij's Welcome screen again when restored.
_Avoid_: Terminal window, shell tab

**zmx Sessions**:
A temporary live list of named zmx sessions that can attach a session to a Terminal Board or end one session. It groups child sessions under their root session; a missing root remains visible as a group.
_Avoid_: Session manager, terminal tab list

**Notification**:
A temporary message from a Terminal Board that calls attention to an event while Den Browser is running. It appears in the Den's notification list and can return focus to its originating Board, including when that Board is on another Desk; Notifications are not retained after Den Browser exits.
_Avoid_: Toast, terminal output, log, history entry

**Board Label**:
A user-visible label for a board's task context. A board label may be inferred from a sheet or set by the user.
_Avoid_: Tab title, page title, board name

**Board Width**:
The horizontal size of a board within a desk. A board width can be adjusted to fit the work.
_Avoid_: Window size, pane size

**Anchor Board**:
A user-designated Board within a Desk that acts as a return anchor during horizontal navigation across Boards. A Desk has at most one Anchor Board at a time.
_Avoid_: Marked Board, Pinned Board, Home Board

**Sheet**:
A unit of content held and presented by a Board. A Sheet is not limited to web content; its content kind is determined by the Board kind.
_Avoid_: Content, Board Content, Page, view, document

**Sheet Stack**:
The back-forward sequence of Sheets within a Web Board.
_Avoid_: Browser history, tab stack, card stack

**Current Sheet**:
The Sheet currently presented by a Board. On a Web Board it is the selected Sheet in the Sheet Stack; on a single-sheet Board it is that Board's one Sheet.
_Avoid_: Active page, top page, visible sheet

**First Sheet**:
The URL held by a Web Board when it was created. It remains that Board's fixed return point independently of the Current Sheet and may be absent on Boards restored from older data.
_Avoid_: Home page, bookmark, browser history

**Recent**:
A Profile-owned list of inputs recently used to open new Boards. It is ordered by most recent use and lets the Profile open another Board from the same web, Terminal, Zellij, or zmx input.
_Avoid_: History, Used Board, Recent Board, Starting Point, Board Start

**Recent Item**:
An input retained in Recent for opening another Board, including a URL, search term, Terminal location, Zellij session intent, or zmx session intent.
_Avoid_: Recent Entry

**Essential**:
A user-named input kept for repeatedly starting a Board from Den Mode. An Essential may be a URL, search term, Terminal location, Zellij session intent, or zmx session intent; unlike a Recent Item, it is intentional and named rather than automatically retained.
_Avoid_: Quick Launch, Board Starter, bookmark, site shortcut

**Essentials**:
The app-wide collection of Essentials available from Den Mode through the reserved Essentials Prefix.
_Avoid_: launcher, favorites, saved tabs

**Drawer**:
A Den-wide place for material whose Desk or Board context is not yet settled. It remains available across Desk changes without becoming part of a Desk layout.
_Avoid_: Inbox, Temporary Desk, scratch workspace, clipboard

**Drawer Item**:
Web material held in the Drawer before it is placed into an established context or discarded. A Drawer Item is not implicitly unread, actionable, or temporary in storage.
Web material enters the Drawer when it is kept there. Keeping it does not change the Current Sheet or Desk layout.
_Avoid_: Inbox item, task, bookmark, history entry

**Drawer Preview**:
The temporary live web presentation expanded beneath a Drawer Item in one Profile window. Its selection and live state belong to that window; the underlying Drawer Item remains Den-wide.
_Avoid_: Board, floating Board, temporary Desk

**Drawer Placement**:
Creating a Board from a Drawer Item in the Focused Desk. The placed item leaves the Drawer.
_Avoid_: Restore, open tab, move to workspace

**Drawer Discard**:
Releasing a Drawer Item without placing it into a Desk or Board context. A discarded Drawer Item remains available in the current app run's transient restoration history, which retains up to ten items.
_Avoid_: Complete, archive, close tab

**Drawer Restoration**:
Returning the newest discarded Drawer Item to the Drawer. Repeated restoration returns older discarded items from the current app run; the history is not persisted across relaunches. Restoration preserves Den Mode when invoked there.
_Avoid_: Undo, reopen tab, restore Board

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
The keyboard context in which the Current Sheet receives input instead of Den, regardless of Board kind.
_Avoid_: Normal mode, browser mode

**Vim-style Sheet Navigation**:
An optional keyboard interaction style for navigating within the Current Sheet of a Web Board. It is distinct from Den Mode and board navigation.
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

**Focus Mode**:
A temporary Den presentation that keeps the Focused Board clear while visually de-emphasizing other Boards' Sheets. It does not change Desk layout, Board focus, or keyboard ownership.
_Avoid_: distraction-free mode

**Den Mode Toggle**:
The action that switches keyboard ownership between Sheet Input and Den Mode.
_Avoid_: Leader, prefix, mode key

**Board Removal**:
Taking a Board off its Desk and ending the live activity of its Sheets. Removing a Terminal Board terminates its process without confirmation.
_Avoid_: Close tab, delete page, trash

**Recently Removed Board**:
A Board removed from a Profile's Den during the current app run and still available for restoration. A Profile can retain up to ten Recently Removed Boards.
_Avoid_: Closed tab, trash, Held Board, undo history

**Board Restoration**:
Returning a Recently Removed Board to a Desk with its saved identity, label, width, and persisted content; restoration starts with the newest available Board, and repeated restoration can return older Recently Removed Boards. A restored ordinary Terminal Board starts a new Terminal Session from its saved Working Directory; a restored Zellij Board starts Zellij from its persisted session name or Welcome screen, and a restored zmx Board reconnects to its persisted session name.
_Avoid_: Undo, reopen tab, restore Sheet Stack
