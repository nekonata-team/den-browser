---
status: accepted
---

# Use one `g` prefix for Essentials

Den Browser represents repeatedly used Board inputs as app-wide named Essentials rather than adding more configurable Den Mode commands or overriding existing `Command` shortcuts. Essentials are selected in Den Mode with one reserved `g` prefix followed by one logical key; `g` is the only additional Den Mode prefix, and the existing single-key commands and `Command` actions remain unchanged.

The `g` prefix is an explicit temporary input context, not a timed leader key: `Escape` cancels it, a registered case-sensitive key starts the selected Board input in the active Profile window, and an unregistered key shows a warning Toast before returning to Den Mode. Shift produces an uppercase key, following Vim's case-sensitive command convention. The Essentials settings live separately from the general Shortcuts settings because Essentials are named Board-starting objects, not changes to Den Mode navigation bindings. The prefix reuses the established Board input forms—URLs, search terms, Terminal locations, and Zellij session intents—and does not introduce a general prefix framework.

## Considered Options

- `Command` plus an arbitrary key was rejected because it expands the collision surface around entrenched application and browser shortcuts.
- `e` as the prefix was rejected because `e` already edits the Focused Board link.
- Multiple prefixes or timed multi-key sequences were rejected to keep Den Mode's routing model small and predictable.

## Consequences

- `g` is reserved for the Essentials Prefix even when no Essential is configured.
- Existing `Command` shortcuts keep their current meaning in every keyboard context.
- An Essential can start a Web, Terminal, or Zellij Board without opening the Open Board panel; direct-launch failure handling must therefore be visible outside that panel.
