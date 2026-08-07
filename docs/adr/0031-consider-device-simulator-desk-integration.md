---
status: proposed
---

# Consider device simulator integration with Desks

Native application debugging may benefit from arranging multiple Android Emulator or iOS Simulator instances with long-running web material such as documentation, issue trackers, logs, and AI tools, then restoring that arrangement with its Desk. The required presentation remains undecided: embedding simulators in the Board Strip would require Den Browser to own screen capture and input forwarding, while managing external simulator windows would require Accessibility permissions and reliable window identity, placement, and lifecycle handling.

No simulator integration is currently accepted. Work is deferred while higher-priority product behavior proceeds. Reconsideration must first decide whether simulator windows need to appear literally among Boards or whether Desk-managed external windows satisfy the debugging workflow; until then, a Board remains a web work surface with a Sheet Stack under [ADR 0001](./0001-companion-browser.md) and [ADR 0002](./0002-paper-workspace-metaphor.md), and `BoardState` and `BoardRuntime` remain web-specific.
