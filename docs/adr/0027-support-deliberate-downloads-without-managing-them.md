---
status: accepted
---

# Support deliberate downloads without managing them

Den Browser supports deliberate file downloads from a Current Sheet. File downloads are intermittent but ordinary parts of long-running web work. Requiring another browser whenever a site provides a file would interrupt that work and conflict with Den Browser's purpose as a companion for sustained web tasks.

Supporting downloads does not make Download management part of the Den work model. Each download uses the macOS save panel with the filename suggested by the site. While a download is active, Den Browser shows its filename and WebKit-reported progress in the window's bottom-right feedback stack; progress is indeterminate when the total size is unknown. Completion or failure is reported with a Toast. Den Browser does not provide an automatic destination, history, or resume support. A Download is not a Den, Desk, Board, or Sheet concept and is not persisted in `DenState`.

The app is unsandboxed per [ADR 0032](./0032-embed-terminal-boards-with-libghostty.md). Downloads still use a destination explicitly selected through the save panel or the Board-scoped CLI save-dialog commands. Native replacement uses the panel's normal confirmation; CLI replacement requires `--overwrite`. Pending save requests are live runtime state, resolve once through either interface, and are cancelled when their runtime is disposed.

`BaseWebRuntime` retains one `DownloadHandler` and assigns it as the `WKDownloadDelegate` for public and context-menu downloads. The Handler owns progress observation and temporary-file cleanup, and delegates save-panel presentation, destination validation, and pending responses to `DownloadSaveDialogs`. Runtime disposal cancels pending responses and cleans up downloads. Boards and the Drawer Peek share this integration, and placement continues the same Handler while notifications follow the current owner. The download destination and lifecycle do not enter persisted Profile or Den state.

On macOS, WebKit creates downloads from its built-in context menu outside the public navigation callbacks. Den Browser implements WebKit's private `_webView:contextMenuDidCreateDownload:` navigation-delegate selector only to attach the same `WKDownloadDelegate` used by public download paths. Replacing the built-in menu would require duplicating WebKit hit testing and download initiation, while leaving the selector unhandled silently cancels the download. If WebKit removes the selector, context-menu downloads may stop working without affecting public navigation-initiated downloads.

This decision narrows the download exclusion in [ADR 0001](./0001-companion-browser.md). [ADR 0033](./0033-support-local-file-sheet-urls.md) later permits local `file://` Sheets, but downloads remain distinct: their destinations and lifecycle do not enter persisted Den state.
