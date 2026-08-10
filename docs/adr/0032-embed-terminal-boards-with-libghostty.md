---
status: accepted
---

# Embed Terminal Boards with libghostty

Den Browser supports Terminal Boards beside Web Boards in the same Desk. The app embeds `GhosttyTerminal` from the exact `libghostty-spm` 1.3.2 package and gives each Terminal Board its own controller and surface. Terminal processes live until their Board, Profile Window, or app closes. Ordinary Terminal Boards persist only the latest reported Working Directory; Zellij Boards persist an optional session name.

The app disables App Sandbox because a normal developer Shell must access the user's files and launch ordinary child processes. Hardened Runtime, Developer ID signing, and notarization remain required. Existing Sandbox-container data is not migrated before 1.0.

Ghostty configuration is loaded from its standard XDG and macOS paths. Named bundled themes resolve through the pinned `GhosttyTheme` catalog. Ghostty window, tab, and split concepts are not exposed.

## Consequences

Terminal Boards share the user's permissions, so web content and terminal processes now coexist in an unsandboxed application. `libghostty` and its Swift wrapper are not treated as stable public APIs; upgrades remain pinned and require build, interaction, performance, signing, and architecture checks.
