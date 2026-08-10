---
status: accepted
---

# Centralize Profile keyboard routing

Profile-window key events use one AppKit monitor, a side-effect-free `KeyboardRouter`, typed routing decisions, and shared `AppAction` execution with SwiftUI Commands. This makes Den Mode ownership and forwarding exceptions inspectable in one place and prevents embedded Web or Terminal responders from intercepting app actions such as unmodified comma for Settings.

Den Browser retains its logical-character shortcut model and focused local recorder instead of adopting `KeyboardShortcuts`, whose physical-key and global-hotkey model does not match the layout-independent persistence and Den Mode capture rules established by ADR 0016. The living implementation rules are defined in [keyboard-input.md](../keyboard-input.md).
