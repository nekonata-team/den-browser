---
status: accepted
---

# Adopt Agent-Browser Snapshot and Interaction Model

Den Browser adopts the "Snapshot + Ref" interaction model popularized by agent-native browser tooling (such as `agent-browser`) for its bundled `den` command-line tool. All page-level interactions are nested under the existing `den sheet` domain to preserve Den's ubiquitous language (`CONTEXT.md`).

Because macOS `WKWebView` does not expose Chrome DevTools Protocol (CDP), semantic page inspection is implemented via lightweight JavaScript injected directly into the active Web Board's web view. The `den sheet snapshot` command traverses the DOM, discovers visible interactive elements (buttons, links, inputs, selects, ARIA roles), and assigns compact, deterministic reference identifiers (`@e1`, `@e2`). This representation reduces token consumption by up to 90% compared to raw HTML or extensive accessibility dumps, enabling coding agents to observe and act with minimal context overhead.

Actions (`den sheet click <ref|selector>` and `den sheet fill <ref|selector> <text>`) resolve target elements by their assigned reference or a fallback CSS selector, dispatching synthetic bubbling mouse and input events compatible with modern reactive frameworks (e.g. React, Vue). Keyboard operations (`den sheet press <key>`) simulate critical keystrokes such as `Enter` and `Escape`. Navigation history (`den sheet back` / `forward`), viewport positioning (`den sheet scroll [direction]`), deterministic synchronization (`den sheet wait <duration-or-selector>`), and visual capture (`den sheet screenshot [path]`) round out the autonomous browsing toolkit.

Creation commands (`den board new <url>`) output the newly generated identifier directly on standard output, adhering to UNIX piping conventions and allowing agents and scripts to compose workflows cleanly. Finished boards can be discarded cleanly with `den board close [<id>]`.
