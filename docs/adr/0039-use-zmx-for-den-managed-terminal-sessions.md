---
status: accepted
---

# Use zmx for Den-managed persistent terminal sessions

Den Browser adds zmx Boards as a distinct Terminal Board kind. `:zmx <session>` runs `zmx attach <session>`, so Den owns the Board-to-session relationship while zmx provides process and terminal-state persistence without adding windows, tabs, or splits. Zellij remains supported as a sibling Board whose session discovery and lifecycle stay inside Zellij; both kinds persist only their named session intent.
