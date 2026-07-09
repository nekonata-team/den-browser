# Liquid Glass Review

This review checks the HTML prototype against Apple's Liquid Glass guidance and SwiftUI's available Liquid Glass APIs.

## Guidance to follow

- Use Liquid Glass for the navigation and control layer that floats above app content.
- Keep the content layer clear and legible; content should remain the center of attention.
- Avoid glass on glass. When controls sit on a glass surface, use fills, transparency, and vibrancy rather than applying another glass material.
- Prefer the regular glass variant for general controls. Use clear glass only when media-rich content, dimming, and bright foreground content make it legible.
- Tint selectively for primary emphasis. Avoid tinting every control.
- Use adaptive separation near scrolling content so labels and controls stay readable.
- Respect accessibility settings such as reduced transparency, increased contrast, and reduced motion through system materials where possible.

## Prototype assessment

- Good: Boards use opaque sheet surfaces, so web content stays readable.
- Good: The Den controls are visually separate from the sheets and act as a floating control layer.
- Good: Focused board treatment uses a small accent instead of tinting every control.
- Fixed: The first prototype used a full-width translucent chrome bar with translucent controls inside it. This has been changed toward separate glass islands to avoid glass-on-glass.
- Watch: The board header currently behaves like a toolbar inside each board. In SwiftUI, this should use regular glass only if it remains a control/navigation layer, not as decorative chrome.
- Watch: Liquid Glass over `WKWebView` content must be tested directly. Native SwiftUI glass may behave differently when compositing over embedded AppKit views.

## SwiftUI implementation direction

Use SwiftUI's system glass APIs on macOS 26+ instead of recreating the HTML blur stack by hand:

```swift
GlassEffectContainer {
    HStack {
        Button("API Research") {}
            .buttonStyle(.glass)

        Button("AI Wall") {}
            .buttonStyle(.glassProminent)

        Button("Writing") {}
            .buttonStyle(.glass)
    }
}
```

Likely mappings:

- Desk switcher: `GlassEffectContainer` with `.buttonStyle(.glass)` and one `.glassProminent` active item.
- Command/search control: `.glassEffect(.regular, in: .rect(cornerRadius: ...))`.
- Floating status overlay: `.glassEffect(.regular)` with restrained text and no nested glass controls.
- Primary action or focused state: `.regular.tint(...)` or `.glassProminent`, used sparingly.
- Board sheets: opaque or app/content material, not Liquid Glass.
- Board headers: regular glass or opaque toolbar depending on legibility over live web content.

## Open PoC checks

- Verify Liquid Glass overlays remain legible over live `WKWebView` sheets.
- Verify glass controls adapt correctly in dark and light appearances.
- Verify reduced transparency, increased contrast, and reduced motion produce usable results.
- Verify keyboard focus rings and focused board indicators are clear without relying only on color.
