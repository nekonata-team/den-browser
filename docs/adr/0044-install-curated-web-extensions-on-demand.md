---
status: accepted
---

# Install Curated Web Extensions on Demand

Bundling MV3 WebExtensions directly within the application binary or resource bundle imposes substantial startup latency, CPU usage, and storage overhead: WebKit must unpack and parse multi-megabyte JSON rule sets and asset files before initial Sheet navigation can begin.

Den Browser does not bundle WebExtension assets or archives in its repository or application bundle. Instead, curated WebExtensions follow the standard browser installation model:

1. WebExtensions are opt-in and downloaded on demand when the user enables them from Settings.
2. The downloaded archive is unpacked once into `~/Library/Application Support/Den Browser/Extensions/<id>/`.
3. `MV3WebExtensionHost` loads the extension directly from the unpacked filesystem directory using `WKWebExtension(resourceBaseURL:)`, eliminating repeated decompression overhead during app startup.
4. If an extension is not installed or enabled, Den Browser starts with zero WebExtension runtime overhead.
