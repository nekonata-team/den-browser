---
status: accepted
---

# Provide an Interactive Tutorial Board

## Decision

An empty Desk cannot teach Den's primary operations through use alone. Provide at most one app-owned Tutorial Board per Den, launchable from an empty Desk or with `:tutorial` in Open Board. The first release contains a Getting Started checklist. When more tutorials are added, the same Board can present them as a selectable catalog; each keeps its checklist for the current app run.

Tutorial Boards and their checklist progress are session-only and are not written to Profile JSON or Desk Presets. Reopening either entry point during the same app run focuses the existing Tutorial Board and retains its progress. A new app run starts without a Tutorial Board; users can open a new one from either entry point.

## Operation events

`AppAction` remains a request/intent. A Den operation emits a typed `DenOperationEvent` only after it succeeds; receiving an action request does not count as completion. `DenStore` handles the event synchronously: it advances matching tutorial progress and forwards the value through one callback on the profile's shared `DenStorage`, following the existing runtime event-callback pattern. This is a direct in-process callback, not a dynamic subscriber registry, so multiple windows share the same callback. Operation success does not depend on consumers. Do not add Combine publishers or `AsyncStream`.

Getting Started guides users to create one Web Board from the Board Strip's `+`, move focus between it and the Tutorial Board with a keyboard shortcut, and create a Desk from the Desk Switcher's `+`. The Tutorial Board is the first Board, so one new Board is enough to practice focus movement. After these required steps, users can optionally explore Den Mode and open its Keyboard Shortcuts guide with `?`, or open a Terminal Board. Advance each required step only on its matching successful event. Board navigation counts only when focus actually moves. Viewing Keyboard Shortcuts in Den Mode completes its optional step. Events carry coarse operation data only; never include keystrokes, URLs, searches, terminal input, clipboard contents, or other user content.

## Consequences

Use Den's own tutorial material rather than relying on third-party demo sites. Keep Den operations synchronous. If future analytics needs asynchronous delivery, its consumer can enqueue events without making Den operations asynchronous.
