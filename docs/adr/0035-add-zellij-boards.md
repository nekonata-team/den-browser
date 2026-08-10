---
status: accepted
---

# Add Zellij Boards as a Distinct Terminal Board Kind

Den Browser treats Zellij as a distinct Board content kind rather than as an optional launch parameter on every Terminal Board.

`:zellij` creates a Zellij Board and runs `zellij -l welcome`. `:zellij <session>` creates a named Zellij Board and runs `zellij attach --create <session>`. A named session is persisted and reused after Den restoration. An unnamed Board persists no Welcome selection, so restoration shows Welcome again.

Den delegates session selection, creation, and lifecycle to Zellij. It does not parse the Welcome screen or infer which session the user selected. Zellij Boards use the same libghostty terminal surface as ordinary Terminal Boards, but set Ghostty's `command` directly to the configured absolute Zellij executable and arguments. Ordinary Terminal Boards keep their existing launch behavior.

Zellij is intentionally modeled as a sibling of the ordinary Terminal Board. Future terminal multiplexers can add their own Board kind without introducing dead parameters or making the current Terminal Board abstraction pretend that all multiplexers share the same lifecycle.

The persisted model records only the optional named session, not a live Zellij process or the selection made in Welcome. Relaunching Den restores the useful named-session intent while keeping Welcome-owned discovery and session management inside Zellij.

The Zellij executable is an external runtime dependency configured in Den's Terminal settings as an absolute path. If the path is empty or non-absolute, Den keeps the request in the open-Board panel and asks for the setting. An absolute path that does not exist is passed through to Ghostty and displays its process error. Runtime behavior should be covered by exploratory validation on a machine with Zellij installed.
