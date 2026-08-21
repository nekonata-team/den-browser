---
layout: ../layouts/LegalLayout.astro
title: Privacy Policy
date: August 22, 2026
---

Den Browser is built with a **local-first, privacy-by-default** philosophy. We believe that your browsing history and session data should remain entirely under your control.

## 1. Information Collection and Transmission

Den Browser does not collect personal information or telemetry, and does not transmit browsing history, visited URLs, terminal commands, or other usage data to our servers or third-party services.

Den Browser stores local data in separate macOS-managed locations:
* Profile and Den state—including Profile settings, Desk, Board, and Drawer layouts, Current Sheet URLs, Terminal Board working directories and Zellij/zmx session names, Personal Desk Presets, and Recent items—are stored as JSON under `~/Library/Application Support/Den Browser/Profiles/`. This directory contains `profile-index.json` and one `<profile-id>.json` document per Profile.
* App-wide preferences—including shortcuts, appearance, Sheet Navigation, content blocking, terminal executable paths, and Essentials—are stored in macOS `UserDefaults` for the `dev.nekonata.denbrowser` application.
* Cookies, caches, local storage, saved sign-in credentials, and WebExtension data are owned by each Profile's persistent `WKWebsiteDataStore` and managed by WebKit. They are not stored in the Profile JSON documents.

Live `WKWebView` objects, terminal processes, terminal screens, scrollback, and transient restoration history are not persisted by Den Browser. A shell, Zellij, or zmx session may have its own files or history according to the user's configuration; those are not managed by Den Browser.

## 2. WebKit and Site Data

Den Browser utilizes Apple's native **`WKWebView` (WebKit)** rendering engine to load web pages.
* Profile separation in Den Browser uses isolated `WKWebsiteDataStore` instances. Data from one Profile cannot leak into or be accessed by another Profile.
* We do not have access to, nor do we store, any passwords or credentials used within the browser.

## 3. Built-in Content Blocking (uBlock Origin Lite)

Den Browser includes **uBlock Origin Lite (uBOL)** as an optional, built-in content blocker.
* **Opt-in only**: Content blocking is disabled by default and must be explicitly enabled by the user in Settings.
* When enabled, content blocking runs entirely on your device according to local declarative rule lists.
* It does not transmit your browsing history, visited URLs, or page content to any external servers.

## 4. Terminal Sessions

Terminal Boards execute locally on your Mac using normal user permissions. Ghostty terminal rendering and shell processes run locally without any external logging or telemetry.

## 5. Third-Party Websites

When using Den Browser to access third-party websites, those sites may collect cookies, IP addresses, and other identifiers in accordance with their own respective privacy policies.

## 6. Updates to this Policy

We may update this Privacy Policy from time to time. Any changes will be published directly to this page and will reflect the local-first nature of the software.

## 7. Contact Us

If you have any questions or suggestions about our Privacy Policy, do not hesitate to contact us through our [GitHub Repository](https://github.com/nekonata-team/den-browser).

## 8. Revision History

* **August 22, 2026**: Clarified that uBlock Origin Lite integration is opt-in, and added details regarding Terminal sessions and local storage scope.
* **July 20, 2026**: Initial release of the Privacy Policy.
