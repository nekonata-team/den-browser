# Keyboard Input

This document is the implementation contract for keyboard input. User-visible bindings belong in [shortcuts.md](./shortcuts.md); the reasons for architectural choices belong in [ADR 0036](./adr/0036-centralize-profile-keyboard-routing.md).

## Canonical flow

Profile-window key events follow one path:

```text
NSEvent
  -> KeyboardController
  -> KeyEvent + InputContext + ShortcutConfiguration
  -> KeyboardRouter
  -> InputDecision
       -> perform(AppAction)
       -> consume(InputReason)
       -> forward(InputDestination)
```

`KeyboardController` is the AppKit adapter. It normalizes the event, snapshots the current input context, calls `KeyboardRouter`, and applies the decision. It must not contain key policy or mutate `DenStore` directly.

`KeyboardRouter` owns Profile-window key precedence. It is side-effect free: it receives values and returns exactly one `InputDecision`. It must not reference UI objects, call `DenStore`, or open windows.

`AppAction` names input-reachable application behavior. `AppActionHandler` is the only keyboard path that performs these actions. SwiftUI `Commands` must use the same action when a menu item and a key event represent the same behavior. Menu-only operations do not need an `AppAction`.

Shortcut recording is configuration input, not an action entrance. It updates `AppPreferences`; the next event receives the effective values through `ShortcutConfiguration`.

## Ownership and precedence

Routing must preserve this order:

1. Fullscreen, pending confirmations, native application commands, and text-entry panels receive their explicitly forwarded keys.
2. Dragging and exclusive temporary contexts consume keys they own. Their allowed cancellation and movement keys become `AppAction` values.
3. Configurable app-wide shortcuts take priority over Sheet Input and Terminal Input while a Profile window is active.
4. Den Mode owns every remaining key. A mapped key performs an action; an unmapped key is consumed.
5. Sheet Input, Terminal Input, Drawer Preview input, and filter text fields receive only events explicitly forwarded to them.

Den Mode actions must never be implemented by forwarding an event and relying on a SwiftUI menu item to catch it. In particular, unmodified comma performs `openSettings` and is consumed before a Sheet or Terminal can receive it.

## Enforced rules

- `KeyboardController` owns the only runtime `keyDown` local monitor for Profile windows.
- The shortcut recorder may install a second local monitor only while recording inside Settings and must remove it when recording ends or the window resigns key status.
- New routing exceptions must be represented by a typed `InputDestination` or `InputReason`; ad hoc early returns are not allowed.
- Shortcut persistence uses logical characters or named special keys plus modifiers. Do not persist physical key codes.
- Do not add global hotkeys without a new architectural decision.
- Do not log raw keys, composed text, or forwarded terminal and Sheet input.
- Native SwiftUI controls may handle local navigation or editing only after the Router has forwarded the event to their input destination.

The exhaustive decision and action enums, the pure Router boundary, focused tests, and the single runtime monitor provide enforcement beyond code review.

## Diagnosing input bugs

Inspect the path in this order:

1. Confirm that the Profile-window `NSEvent` reaches `KeyboardController`.
2. Inspect the normalized `KeyEvent`, especially logical character, special key, modifiers, repeat, and marked-text state.
3. Inspect `InputContext`, including Den Mode and any exclusive temporary context.
4. Inspect the effective `ShortcutConfiguration`, including explicit unassignment.
5. Inspect the returned `InputDecision` and its reason or destination.
6. For `.perform`, inspect `AppActionHandler` and the resulting `DenStore` or system effect.
7. For `.forward`, inspect only the named destination's responder path.

When changing routing, add a Router decision test. Add an action-result test when behavior mutates Den. Add a UI test when the regression crosses AppKit, SwiftUI Commands, WebKit, or Terminal responder boundaries. Run `just check`; run the focused `just ui-test` target for affected UI behavior.
