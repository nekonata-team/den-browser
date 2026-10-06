---
status: accepted
---

# Organize source by product ownership and local layers

The large `Features/Den` group obscured Desk, Board, Drawer, and Den-wide responsibilities. Organize the source primarily by product ownership, with Web, Terminal, Inspection, and Tutorial implementations under Board and shared Web behavior in its own group.

Within a feature, use Domain for product state and rules, Application for operation sequencing, Presentation for views and display behavior, and Infrastructure for persistence or runtime integration. Domain remains independent of Application, UI frameworks, and live runtime objects. Keep small groups flat when layers add only scaffolding. Feature folders are source ownership groups in one Swift target; they do not imply independent modules or stores. Do not add stores, protocols, repositories, or coordinators merely to mirror directories. Existing views may continue using `DenStore`, and Den remains the entry point for operations spanning product groups.

App assembles scenes and command integration; IPC owns external command boundaries; Platform contains only feature-independent operating-system integration; Design contains shared visual resources and controls. Promote code across these boundaries only when its responsibility and dependencies support the move. Keep source moves separate from behavior changes, and preserve persisted formats and runtime behavior.
