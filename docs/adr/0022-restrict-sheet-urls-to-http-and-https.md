---
status: accepted
---

# Restrict sheet URLs to HTTP and HTTPS protocols

Den Browser restricts Sheet URLs to `http` and `https` schemes, explicitly declining to support the local file scheme (`file://`). This decision aligns with the product's positioning as a companion browser for long-running web work rather than a general-purpose browser or document viewer (see [ADR-0001](./0001-companion-browser.md)).

Because Den Browser explicitly avoids the surface area of a general-purpose browser—such as managing local downloads or acting as a default document reader—supporting the `file://` scheme falls outside of its scope. Doing so would introduce substantial technical and security complexity under the macOS App Sandbox:

1. **Sandbox Access Persistence**: Under the macOS App Sandbox, the app cannot access arbitrary local paths unless granted via `NSOpenPanel` or drag-and-drop. While temporary access is granted, it is lost when the app terminates. Restoring these URLs across app restarts would require generating, serializing, and resolving Security-Scoped Bookmarks, significantly complicating the local persistence model (`DenState`).
2. **Preset Portability**: Personal Desk Presets containing local `file://` URLs would fail when exported, shared, or resolved on a different machine (or even the same machine if file paths or access permissions change).
3. **Alternative Solutions**: For local web development, developer workflows typically rely on local development servers (e.g., `http://localhost:xxxx`), which are fully supported under the `http` scheme.

Therefore, Sheet URLs will continue to be restricted to standard web protocols (`http` and `https`) to maintain a clean, portable, and secure state representation, preserving the product's focus on its core companion workflows.
