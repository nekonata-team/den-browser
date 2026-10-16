# Keyboard Input

Keyboard input follows the contract below. Bindings are listed in [shortcuts.md](./shortcuts.md); architectural reasons are recorded in [ADR 0036](./adr/0036-centralize-profile-keyboard-routing.md) and [ADR 0038](./adr/0038-use-one-g-prefix-for-essentials.md).

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

`KeyboardController` normalizes AppKit events, snapshots input context, calls `KeyboardRouter`, and applies its decision. It must not contain key policy or mutate `DenController` directly. Each Profile window registers its mounted `DenWindowModel`; events use the instance associated with `event.window`. `InputContext` receives application state from `DenController` and presentation state from `DenWindowModel` as separate inputs. The Model owns neither the Controller nor shared Store; see [the ownership boundary](./architecture.md#shared-state-and-presentation-package-boundaries).

`KeyboardRouter` determines Profile-window key precedence from input values, returning exactly one `InputDecision` without side effects. It must not reference UI objects, call `DenController`, or open windows. Den Mode's `g` or Vim-style Sheet Navigation's `o` enters the temporary Essentials Prefix context. Up and Down move the focused Essential, Return launches it, Option-Return opens its URL or search in Drawer, and a configured key (with Shift for uppercase) launches its matching Essential directly. Escape exits the prefix.

`AppAction` names input-reachable application behavior. `AppActionHandler` is the only keyboard path that performs these actions. It receives the window Controller and Model explicitly, using the Model for UI workflows and the Controller for application operations. SwiftUI `Commands` use the focused Controller, Model, and action when a menu item and a key event represent the same behavior. Menu-only operations do not need an `AppAction`.

The Notifications popover uses SwiftUI focus and `onKeyPress` to receive input in its separate window.
`KeyboardController.handleNotificationKeyPress` normalizes these events for the same Router and action path
without adding a local monitor. This adapter is limited to Notifications, which has no text editor.
Up/Down select, Return opens the selected Notification, and Escape dismisses.

Shortcut recording updates `AppPreferences` without dispatching actions; the next event uses the effective values through `ShortcutConfiguration`.

Universal Search is an exclusive temporary input context. Its Router forwards text editing and all marked-text
composition events to the native field, consumes Up/Down for result selection, Return for execution, Option-Return for opening a URL, search, or Essential in Drawer, and Escape
for dismissal. Dismissal preserves the previous Den Mode state. `Command-P`, `Command-Shift-P`, Den Mode's `:`,
the menu items, and the toolbar button use the same window-local presentation. See [Universal Search](./universal-search.md).

## Ownership and precedence

Routing must preserve this order:

1. Fullscreen, pending confirmations, native application commands, and text-entry panels receive their explicitly forwarded keys.
2. Dragging and exclusive temporary contexts consume keys they own. Their allowed cancellation and movement keys become `AppAction` values.
3. Configurable app-wide shortcuts take priority over Sheet Input while a Profile window is active.
4. Den Mode owns every remaining key. The reserved `g` enters the Essentials Prefix; its next key, including its case, is handled by that temporary context. Other mapped keys perform an action; an unmapped key is consumed with a warning Toast.
5. Sheet Input, Drawer Peek input, and filter text fields receive only events explicitly forwarded to them.

Den Mode actions must never be implemented by forwarding an event and relying on a SwiftUI menu item to catch it. In particular, unmodified comma performs `openSettings` and is consumed before Sheet Input can receive it.

## Enforced rules

- `KeyboardController` owns the only runtime `keyDown` local monitor for Profile windows.
- The shortcut recorder may install a second local monitor only while recording inside Settings and must remove it when recording ends or the window resigns key status.
- New routing exceptions must be represented by a typed `InputDestination` or `InputReason`; ad hoc early returns are not allowed.
- Confirmation dialogs must provide a default action for Return and a cancel action for Escape. While a confirmation is presented, the Router forwards both keys to the native dialog.
- Shortcut persistence uses logical characters or named special keys plus modifiers. Do not persist physical key codes.
- Do not add global hotkeys without a new architectural decision.
- Do not log raw keys, composed text, or forwarded Sheet Input.
- Native SwiftUI controls may handle local navigation or editing only after the Router has forwarded the event to their input destination.
- Text-entry panels consume Tab and Shift-Tab traversal to keep focus inside the panel. During IME composition,
  they forward these keys to native text input for conversion.

Decision and action enums, the pure Router, focused tests, and the single runtime monitor support enforcement.

## Diagnosing input bugs

Inspect the path in this order:

1. Confirm that the Profile-window `NSEvent` reaches `KeyboardController`.
2. Inspect the normalized `KeyEvent`, especially logical character, special key, modifiers, repeat, and marked-text state.
3. Inspect `InputContext`, including Den Mode and any exclusive temporary context.
4. Inspect the effective `ShortcutConfiguration`, including explicit unassignment.
5. Inspect the returned `InputDecision` and its reason or destination.
6. For `.perform`, inspect `AppActionHandler` and the resulting Model, Store, or system effect.
7. For `.forward`, inspect only the named destination's responder path.

When changing routing, add a Router decision test. Add an action-result test when behavior mutates Den. Add a UI test when the regression crosses AppKit, SwiftUI Commands, WebKit, or Terminal responder boundaries. Run `just check`; run the focused `just test ui` target for affected UI behavior.
