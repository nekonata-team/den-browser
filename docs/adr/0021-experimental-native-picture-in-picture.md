---
status: accepted
---

# Experimental native Picture in Picture with Board-level control

Den Browser provides an optional, experimental native Picture in Picture (PiP) feature for macOS WKWebView. To bypass standard App Sandbox restrictions and coordinate floating media presentation, the app utilizes the private WebKit preferences interface `_allowsPictureInPictureMediaPlayback` (guarded by dynamic selector checks to prevent runtime crashes if removed in future macOS updates) and registers a temporary sandbox entitlement for `com.apple.PIPAgent`.

Rather than relying purely on system-level triggers (which require discovering hidden web-page shortcuts like double right-clicking to bypass custom site-specific context menus, e.g., on YouTube), Den Browser exposes a "Toggle Picture in Picture" action directly in the Board header's context menu. This action injects a lightweight JavaScript runner into the WKWebView to dynamically discover and toggle the largest active `<video>` element on the page.

Because web DOM layouts (such as nested iframes, Shadow DOM encapsulations, or custom player scripts) can vary heavily, the feature is classified as an opt-in "Experimental" setting. This limits the long-term maintenance cost of diagnosing site-specific playback bugs while delivering a highly visible, native convenience feature for video-intensive workflows.
