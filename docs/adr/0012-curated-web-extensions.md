---
status: superseded
---

# Offer curated web extensions as Features

Superseded by ADR 0013. The Vimium C PoC loaded a `WKWebExtension` context but did not produce usable Sheet navigation, so Den Browser did not validate curated WebExtensions as a product capability.

Den Browser may bundle selected WebExtensions and expose them as optional Features. Each Feature is disabled by default and requires explicit user consent before receiving access to Sheets.

Den Browser does not provide arbitrary extension installation or an extension marketplace. Bundled extension versions are fixed in the app so their code, permissions, licenses, and behavior can be reviewed with the app.

WebExtensions operate within Sheets. They do not own Den concepts or operations: creating, closing, focusing, or moving Boards and Desks remains a Den responsibility, available through Den controls and Den Mode. Den therefore exposes only the minimum browser state required for content injection and rejects extension requests that would mutate Boards or Desks.

The first proof of concept bundles Vimium C 2.12.2 using WebKit's `WKWebExtension` APIs. It validates Sheet-local keyboard navigation before Den considers other curated Features such as content blocking.
