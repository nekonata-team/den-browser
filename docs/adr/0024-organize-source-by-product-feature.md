---
status: accepted
---

# Organize source by product ownership and local layers

Den Browser keeps product ownership as the primary source grouping and uses local layers to distinguish state, operations, views, and concrete runtime integration. The former `Features/Den` grouping held most application code and obscured the differences between Desk, Board, Drawer, and Den-wide composition.

Den now owns aggregate state, shared and window-local application operations, and Den-wide presentation. Desk, Board, and Drawer are sibling source groups. Web, Terminal, Inspection, and Tutorial implementations belong under Board. A separate shared Web group owns URL policy, the base WebKit runtime, and DOM operations used by Web Boards, Drawer Preview, and Sheet Navigation. Sheet remains a content concept rather than a Web-only implementation folder.

Within these groups, Domain contains data and rules, Application sequences operations, Presentation owns views and display-specific extensions, and Infrastructure owns runtime or persistence integration. Small groups remain flat when layers would only add scaffolding. A source group is not automatically an independent Swift module or store: existing views continue to use DenStore, and no new stores, protocols, repositories, or coordinators are introduced to mirror the tree.

Domain code does not depend on UI frameworks or runtime implementation. DenStore remains the application entry point for operations crossing product domains. App assembles scenes, windows, and command integration. Platform contains only feature-independent OS integration. IPC protocol, transport, and application handling have an explicit shared boundary outside Features.

Source moves and declaration extraction preserve behavior and persisted formats. Responsibility changes require their own evidence and review; a folder move alone does not establish an architectural boundary.
