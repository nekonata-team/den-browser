---
status: accepted
---

# Adopt Agent-Browser Snapshot and Interaction Model

Den Browser adopts the "Snapshot + Ref" interaction model popularized by agent-native browser tooling (such as `agent-browser`) for its bundled `den` command-line tool. The original Sheet-oriented command grouping followed Den's domain language at the time. The current placement of Web Board operations under `den board web` is defined in [ADR 0051](0051-structure-den-cli-by-board-kind.md).

Because macOS `WKWebView` does not expose Chrome DevTools Protocol (CDP), semantic page inspection is implemented via lightweight JavaScript injected directly into the active Web Board's web view. The `den board web snapshot` command traverses the DOM, discovers visible semantic elements (landmarks, headings, buttons, links, inputs, selects, and ARIA roles), and assigns compact, deterministic reference identifiers (`@e1`, `@e2`). The default snapshot contains interactive elements; `-i`/`--interactive` selects that form explicitly, while `--full` includes all eligible visible semantic elements. This representation reduces token consumption by up to 90% compared to raw HTML or extensive accessibility dumps, enabling coding agents to observe and act with minimal context overhead.

Actions (`den board web click <ref|selector>` and `den board web fill <ref|selector> <text>`) resolve target elements by their assigned reference or a fallback CSS selector, dispatching synthetic bubbling mouse and input events compatible with modern reactive frameworks (e.g. React, Vue). Keyboard operations (`den board web press <key>`) simulate critical keystrokes such as `Enter` and `Escape`. Navigation history (`den board web back` / `forward`), viewport positioning (`den board web scroll [direction-or-target]`), deterministic synchronization (`den board web wait` with a DOM state, text, load state, URL glob, or JavaScript condition), and visual capture (`den board web screenshot [path]`) round out the autonomous browsing toolkit.

Creation commands (`den board web new <url>`) output the newly generated identifier directly on standard output, adhering to UNIX piping conventions and allowing agents and scripts to compose workflows cleanly. Finished Boards can be discarded with `den board close`, or a specific Board with `den board close --board <id>`.
