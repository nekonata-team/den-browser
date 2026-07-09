# MVP is a macOS-first desktop app

Den Browser's MVP is a macOS-first desktop app for wide screens and keyboard-driven work. We chose this over a web app, mobile app, or broad cross-platform target because the core experience depends on native WebViews, reliable keyboard handling, restoration, and horizontal spatial work. Linux, Windows, and mobile support can be revisited after the Den interaction model proves useful on macOS.

The MVP targets macOS 26 or later. This lets the app use SwiftUI's Liquid Glass APIs directly instead of carrying fallback UI for older macOS versions during the PoC.
