---
status: accepted
---

# Use zmx for Den-managed persistent terminal sessions

Den Browser adds zmx Boards as a distinct Terminal Board kind. `:zmx <session>` runs `zmx attach <session>`, so Den owns the Board-to-session relationship while zmx provides process and terminal-state persistence without adding windows, tabs, or splits. Zellij remains supported as a sibling Board whose session discovery and lifecycle stay inside Zellij; both kinds persist only their named session intent.

Duplicating a zmx Board creates an independent zmx session instead of reconnecting to the source session. Den keeps the source Working Directory and derives the new name from the root session: entering `vi` for `den` creates `den-vi`, while duplicating that child and entering `nvim` creates the sibling `den-nvim`. When the source zmx session is active, its `den.root` label is the authoritative root; if the label is absent, Den falls back to the persisted root session name and then the source session name. The root Board has no root label; child Boards persist the resolved root session name and set the runtime zmx label `den.root` when their session starts. Suffixes accept letters, numbers, `-`, `_`, and `.`. An empty suffix uses a numeric name, and any name collision is advanced to the next available number. Ordinary Terminal, Web, and Zellij duplication behavior is unchanged.
