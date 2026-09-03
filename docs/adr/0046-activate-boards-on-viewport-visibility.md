---
status: accepted
---

# Activate Boards on Viewport Visibility

Den Browser defers instantiating Board runtimes and attaching terminal or web processes until a Board first enters the viewport or gains focus. While Boards reside outside the horizontal scroll viewport, Den Browser suspends their active surface rendering. This eliminates startup CPU saturation caused by concurrent process attachments and reduces ongoing idle resource consumption without altering visible spatial layout.

## Considered Options

- Eagerly attach all Boards in the active Desk immediately. This is simple, but multiple Terminal Boards (e.g., zmx sessions replaying scrollback) or complex web pages saturate CPU for 10–16 seconds on launch and keep display links ticking for invisible surfaces.
- Attach Boards only on explicit focus. This saves work, but adjacent Boards already visible in the viewport appear blank until focused.
- Activate Boards upon entering the viewport (threshold: 0.05) and suspend off-viewport rendering. Boards in view attach immediately; off-screen Boards render structural chrome and connect as soon as scrolling brings them into view, while off-screen surfaces pause Metal display links and web rendering.

## Consequences

Off-screen Boards initially display their header and frame without live content until scrolled into view or focused. Because local process attachment (zmx or WebKit) completes in tens of milliseconds, boards are ready as they scroll to center. Measurements with multiple terminal sessions showed initial CPU peak reduced by ~46% (from 212% to 115%), high-load duration reduced from 16 to 10 seconds, and steady idle CPU reduced from 5–7% to ~3%.
