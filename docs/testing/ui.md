# UI Testing & Exploratory Validation

XCUITest covers native UI boundaries unit tests cannot observe ([ADR 0020](../adr/0020-test-critical-ui-workflows.md)). Exploratory validation covers environment-dependent or visual behavior.

## XCUITest admission rule

Add a UI test only when all three hold (name the boundary and why unit coverage is insufficient):

- Behavior crosses a native boundary (SwiftUI gesture identity, accessibility routing, AppKit/WebKit/Terminal responder handoff).
- A unit test cannot observe the failure at that boundary.
- It proves one independent user-visible workflow and its final outcome.

Ordinary button clicks, styling, shortcut mappings, state transitions, and input permutations do not qualify. For Board activation, send input after the transition and observe a target-specific result; selection state or titles alone do not prove mounted responder handoff.

## Structure & isolation

- Use `BDD.swift` (`Given`/`When`/`Then`); keep mutations in `When` and assertions in `Then`. Put shared UI test helpers alongside scenario files.
- Wait with `assertEventually` / `assertValue`; avoid arbitrary sleeps, focus waits, or repeated input after responder handoff. Paste long text; send rapid unmodified keys in one `typeText` call.
- Use Reduced Motion by default (opt into Standard Motion explicitly when testing animations). UI tests run serially with screen capture disabled.
- Isolate every run: temporary Profiles, isolated defaults suite, non-persistent WebKit data, local URLs, `/bin/zsh -f` (no user Ghostty config).

## Exploratory validation

- Use exploratory checks (Computer Use on macOS) for real websites, auth, downloads, IME/multi-display, Ghostty rendering, Liquid Glass, accessibility, and performance.
- Treat WKWebView content and Ghostty terminal surfaces as external to the app AX tree.
