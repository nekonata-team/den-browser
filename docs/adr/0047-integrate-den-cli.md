---
status: accepted
---

# Integrate Den CLI

ADR-0055 supersedes only this ADR's decision to avoid MCP. The first-party CLI, its bundled distribution, and its user-scoped Unix socket remain accepted.

Den Browser bundles a first-party command-line tool (`den`) inside the application bundle to enable developers and coding agents to inspect and drive Web Boards from Terminal Boards or external shells. Communication between the CLI and the running Den Browser process is routed over a user-scoped Unix domain socket using line-delimited JSON.

Terminal Boards automatically inject spatial context (`DEN_SOCKET`, `DEN_BOARD_ID`) into the shell environment. When invoked without an explicit target, `den` resolves contextually to the adjacent Web Board on the active Desk, removing the need to pass Board identifiers during standard terminal workflows.

The CLI exposes a minimal surface for navigation, text extraction, DOM interaction, and JavaScript evaluation, formatted for human readability in a terminal and structured JSON when piped or requested via `--json`. Full browser automation suites and heavy remote protocols (such as MCP or Chrome DevTools Protocol) are intentionally avoided; unmodeled visual interactions remain delegated to Computer Use.

The `den` binary is built as a Command Line Tool target packaged in `Contents/MacOS/den`. Homebrew Cask links it into the user's `PATH`, and Terminal Boards prepend the bundle path to `PATH` so the CLI is immediately available without manual setup.
