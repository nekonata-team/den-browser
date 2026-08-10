---
status: accepted
---

# Support local file Sheet URLs

Den Browser supports absolute local `file://` URLs as Sheet URLs alongside HTTP and HTTPS. Local file Sheets participate in the existing Board, Recent, Drawer, Desk Preset, restoration, link, and Vim-style Sheet Navigation workflows. The Open Board and Current Sheet URL fields remain the only direct entry points: Den does not interpret filesystem paths, add a file picker, or register as a document reader.

The app accepts `file:///...` and `file://localhost/...`, canonicalizing the latter to a local URL. Relative `file:` URLs and remote file authorities are rejected. Persisted state stores only the URL through the existing Foundation `URL` representation. It does not validate continued existence or add security-scoped bookmarks, so local file Sheets are intentionally machine- and path-dependent.

WebKit loads local content with `loadFileURL(_:allowingReadAccessTo:)`. A file grants WebKit read access to its containing directory; a directory URL grants access to itself. Query and fragment components remain part of the navigation URL but are removed from the read-access URL. This allows ordinary sibling assets while avoiding home-directory or filesystem-wide access.

This supersedes ADR 0022. Its App Sandbox persistence cost no longer applies because Terminal Boards require an unsandboxed app under ADR 0032. Local content and terminal processes share the user's permissions, but each explicit local Sheet load still limits WebKit's file read scope to the selected directory. Files outside that directory require a separate explicit Sheet load. Missing, moved, or inaccessible files remain persisted and fail through WebKit's normal navigation behavior.
