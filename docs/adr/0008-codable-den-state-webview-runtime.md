# Persist Den state separately from WebView runtime

Den Browser should persist desks, boards, labels, widths, current sheet URLs, and focus as Codable Den state, likely in JSON for the MVP. Live WKWebView instances are runtime objects and must not be treated as the source of truth for persisted state. Keeping persisted Den state separate from WebView runtime state makes restoration, testing, and later storage changes simpler.
