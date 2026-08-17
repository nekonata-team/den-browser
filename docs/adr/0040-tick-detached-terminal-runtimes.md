---
status: accepted
---

# Tick Detached Terminal Runtimes at Low Frequency

Den Browser keeps Terminal Sessions alive when their Terminal Board is detached by a Desk change, another Profile Window, the Drawer, or an overview presentation. Because a detached surface may no longer receive its normal display-link-driven libghostty updates, each detached `TerminalRuntime` runs `controller.tick()` once per second until the surface becomes visible again or the runtime is disposed. This preserves terminal wakeups and notifications without rendering hidden surfaces.

## Considered Options

- Stop all updates with the surface. This saves work but can delay or lose libghostty-driven wakeups and desktop notifications.
- Keep a display-rate tick running. This preserves responsiveness but spends unnecessary CPU on every detached Terminal Board.
- Run a low-frequency tick per detached runtime. This preserves the required processing at a bounded cost and matches the ownership of one controller per Terminal Board.

## Consequences

Detached Terminal Boards perform periodic main-actor work even when they are not rendered. A 60-second measurement with approximately 20 additional detached Terminal Boards showed about 6.5–7.3% total Den Browser CPU usage, with a tick-duration median of 1.33 microseconds and a p95 of 24.5 microseconds. This is an operational trade-off, not a persisted Den-state concern.

## Reevaluate

Reevaluate this decision when an upstream libghostty release no longer requires application ticks while a surface's display link is paused. At that point, remove or suppress the detached-runtime tick loop after confirming wakeups, notifications, and Terminal Board lifecycle behavior with focused tests and a runtime measurement.
