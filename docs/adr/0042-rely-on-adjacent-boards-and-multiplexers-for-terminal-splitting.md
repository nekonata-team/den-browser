---
status: accepted
---

# Rely on Adjacent Boards and Multiplexers for Terminal Splitting

Den Browser does not expose built-in terminal pane splitting or a floating terminal panel. It relies on horizontal Board duplication for lightweight multitasking and dedicated terminal multiplexers (Zellij, zmx) for internal pane splitting.

Den's core metaphor is a horizontal strip of visible Boards. Spawning a new shell beside the current one (`Return` to duplicate a Terminal Board in the same working directory) keeps terminal multitasking aligned with the Desk and Board model.

Users needing vertical or horizontal splits, tabbed panes, or detached session lifecycles within a single Board use first-class multiplexer integrations (`:zellij`, `:zmx`). Terminal Boards maintain a strict 1:1 relationship between a Board and a Ghostty terminal surface (`AppTerminalView`), delegating PTY multiplexing and session persistence to external tools rather than duplicating window management in Den.
