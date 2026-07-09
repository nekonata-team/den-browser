# MVP PoC uses WKWebView

Den Browser's MVP PoC uses native macOS WKWebView for sheets. This matches the macOS-first direction, gives us persistent website data through WKWebsiteDataStore, and lets us test the Den interaction model without carrying a full Chromium shell. Electron remains the fallback if WKWebView cannot support the required AI chat workflows, login persistence, or multi-board performance.
